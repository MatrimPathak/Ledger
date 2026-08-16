import 'dart:convert';
import 'package:another_telephony/telephony.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import '../firebase/firestore_service.dart';
import '../ai/claude_service.dart';
import '../notification/notification_service.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/default_categories.dart';
import '../../models/category.dart';
import '../../models/transaction.dart' as tx_model;
import '../../models/payment_mode.dart';
import 'bank_sms_filter.dart';
import 'local_sms_parser.dart';

const double _maxPlausibleAmount = 10000000;

String? resolveBackgroundSmsUid({
  required String? firebaseAuthUid,
  required SharedPreferences prefs,
}) {
  if (firebaseAuthUid != null && firebaseAuthUid.isNotEmpty) {
    return firebaseAuthUid;
  }

  final storedUid = prefs.getString(AppConstants.prefKeyUid);
  if (storedUid != null && storedUid.isNotEmpty) {
    return storedUid;
  }

  return null;
}

// Returns a stable identity key for an SMS message used to prevent duplicate
// processing across background isolate delivery and inbox catch-up.
String _smsFingerprint(SmsMessage msg) {
  final id = msg.id?.toString() ?? '';
  if (id.isNotEmpty) return 'sms:$id';
  // Fallback: content-derived key when the platform omits the ID.
  final addr = msg.address ?? '';
  final body = msg.body ?? '';
  final snippet = body.length > 50 ? body.substring(0, 50) : body;
  return '${addr}_${msg.date ?? 0}_$snippet';
}

/// Content-based dedup hash, independent of device-local fingerprint state
/// (survives app-data clears/reinstalls). Normalizes whitespace/case before
/// hashing so trivial formatting differences between resends of the same
/// bank event still hash identically.
String computeSmsHash(String body) {
  final normalized = body.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  return sha256.convert(utf8.encode(normalized)).toString();
}

bool _isAlreadyProcessed(String fingerprint, SharedPreferences prefs) {
  final stored = prefs.getString(AppConstants.prefKeyProcessedSmsIds) ?? '[]';
  try {
    final list = (jsonDecode(stored) as List).cast<String>();
    return list.contains(fingerprint);
  } catch (_) {
    return false;
  }
}

Future<void> _markProcessed(String fingerprint, SharedPreferences prefs) async {
  final stored = prefs.getString(AppConstants.prefKeyProcessedSmsIds) ?? '[]';
  List<String> ids;
  try {
    ids = (jsonDecode(stored) as List).cast<String>();
  } catch (_) {
    ids = [];
  }
  if (!ids.contains(fingerprint)) {
    ids.add(fingerprint);
    // Cap at 300 entries to prevent unbounded SharedPreferences growth.
    if (ids.length > 300) ids.removeRange(0, ids.length - 300);
    await prefs.setString(AppConstants.prefKeyProcessedSmsIds, jsonEncode(ids));
  }
}

// Returns true for pre-debit notification SMS (e-mandate / NACH). These record
// the upcoming deduction but must NOT affect the account balance because the
// actual debit will arrive as a separate SMS and adjust the balance then.
bool _isPreDebitNotification(String body) {
  final lower = body.toLowerCase();
  return lower.contains('e-mandate') ||
      lower.contains('emandate') ||
      lower.contains('will be deducted') ||
      lower.contains('auto debit') ||
      lower.contains('auto-debit');
}

/// Rejects values that cannot be a real transaction, so a parsing glitch
/// (local or AI) can never silently create incorrect financial data.
bool isPlausibleAmount(double amount) =>
    amount > 0 && amount <= _maxPlausibleAmount;

bool isPlausibleTransactionDate(DateTime date) =>
    date.isBefore(DateTime.now().add(const Duration(days: 1)));

// Looks up a category by slug. If none matches (or no slug is available,
// e.g. a purely local high-confidence parse with no AI categorization),
// falls back to "Other" rather than guessing — the user can always correct
// it, and an honest "Other" is safer than a fabricated category.
Future<Category> resolveOrCreateCategory({
  required String? slug,
  required List<Category> categories,
  required String uid,
  required FirestoreService firestoreService,
}) async {
  final lower = (slug ?? 'other').toLowerCase();
  final existing =
      categories.where((c) => c.title.toLowerCase().contains(lower)).firstOrNull;
  if (existing != null) return existing;

  final defaultEntry = DefaultCategories.list.firstWhere(
    (e) => (e['title'] as String).toLowerCase().contains(lower),
    orElse: () => DefaultCategories.list.last,
  );

  return firestoreService.createCategory(Category(
    id: '',
    userId: uid,
    title: defaultEntry['title'] as String,
    iconCodePoint: (defaultEntry['icon'] as dynamic).codePoint as int,
    colorValue: (defaultEntry['color'] as dynamic).value as int,
    isDefault: false,
    createdAt: DateTime.now(),
  ));
}

// Top-level background SMS handler — runs in a separate isolate
@pragma('vm:entry-point')
Future<void> backgroundSmsHandler(SmsMessage message) async {
  final body = message.body ?? '';
  if (!await BankSmsFilter.looksLikeBankSms(body)) return;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(AppConstants.prefKeyAutoDetect) != true) return;

  // Timestamp watermark: skip if already processed via catch-up.
  final smsTimestamp = message.date;
  if (smsTimestamp != null) {
    final lastProcessed = prefs.getInt(AppConstants.prefKeyLastSmsTimestamp) ?? 0;
    if (smsTimestamp <= lastProcessed) return;
  }

  // Fingerprint dedup: handles null-date messages and concurrent isolate races.
  final fingerprint = _smsFingerprint(message);
  if (_isAlreadyProcessed(fingerprint, prefs)) return;

  // E-mandate / NACH pre-debit notifications are not real transactions — the
  // actual debit arrives as a separate SMS. Skip them entirely so they never
  // appear in the transaction list.
  if (_isPreDebitNotification(body)) {
    await _markProcessed(fingerprint, prefs);
    return;
  }

  // Honour the user's notification preference in the background isolate.
  NotificationService.notificationsEnabled =
      prefs.getBool(AppConstants.prefKeyNotifications) ?? true;

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Already initialized in the main isolate — safe to continue
  }

  await NotificationService.initialize();
  await NotificationService.showProcessingNotification();

  try {
    final uid = resolveBackgroundSmsUid(
      firebaseAuthUid: FirebaseAuth.instance.currentUser?.uid,
      prefs: prefs,
    );
    if (uid == null || uid.isEmpty) {
      await NotificationService.showSmsErrorNotification('Not signed in — open Ledger once to re-authenticate.');
      return;
    }

    final firestoreService = FirestoreService();
    final accounts = await firestoreService.fetchAccounts(uid);
    final paymentModes = await firestoreService.fetchPaymentModes(uid);
    final creditCardAccounts = await firestoreService.fetchCreditCardAccounts(uid);

    final txDate = smsTimestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(smsTimestamp)
        : DateTime.now();
    final sourceMessageHash = computeSmsHash(body);

    // Layer 2/3: deterministic local parsing + confidence scoring.
    final parser = await LocalSmsParser.load();
    final localResult = parser.parse(body, accounts: accounts, paymentModes: paymentModes);

    // Firestore-side dedup, on top of the device-local fingerprint above —
    // catches the case where app data was cleared/reinstalled and the
    // fingerprint list was lost, but the transaction already exists.
    if (localResult.referenceNumber != null) {
      final exists = await firestoreService.transactionExistsByExternalRef(
          uid, localResult.referenceNumber!);
      if (exists) {
        await _markProcessed(fingerprint, prefs);
        return;
      }
    } else {
      final exists = await firestoreService.transactionExistsByHashNearby(
          uid, sourceMessageHash, txDate);
      if (exists) {
        await _markProcessed(fingerprint, prefs);
        return;
      }
    }

    // Layer 4: three-tier routing. High confidence never touches the cloud.
    // Medium confidence sends only a redacted snippet plus whatever the
    // local parser is still unsure about; low confidence (local extraction
    // found too little to build a smaller request from) falls back to the
    // full SMS, same shape as before this rewrite.
    ClaudeParsedResult? aiParsed;
    if (!localResult.isHighConfidence) {
      // This handler only ever runs with the Flutter engine alive
      // (`listenInBackground: false` in SmsService.startListening — true
      // background processing is the native Kotlin pipeline), so the
      // Keystore-backed secure storage used everywhere else in the
      // foreground app is available here too. The plaintext prefs read is
      // a fallback only, for any value written before that migration.
      const secureStorage = FlutterSecureStorage();
      final secureKey =
          await secureStorage.read(key: AppConstants.prefKeyClaudeApiKey);
      final apiKey = secureKey ??
          prefs.getString(AppConstants.prefKeyClaudeApiKey) ??
          AppConstants.claudeApiKeyPlaceholder;
      if (apiKey != AppConstants.claudeApiKeyPlaceholder && apiKey.isNotEmpty) {
        final claudeService = ClaudeService(apiKey);
        final parsed = localResult.isMediumConfidence
            ? await claudeService.parseSmsPartial(
                redactedSmsSnippet: redactSensitiveDigits(body),
                accounts: accounts,
                paymentModes: paymentModes,
                knownAmount: localResult.amount,
                knownDirection: localResult.direction,
                knownPaymentMethod: localResult.paymentMethod,
                knownReferenceNumber: localResult.referenceNumber,
                cacheKey: sourceMessageHash,
              )
            : await claudeService.parseSmsTransaction(
                smsBody: body,
                accounts: accounts,
                paymentModes: paymentModes,
                cacheKey: sourceMessageHash,
              );
        if (parsed != null) {
          aiParsed = ClaudeParsedResult(parsed);
        }
      }
    }

    final resolvedAmount = aiParsed?.parsed.amount ?? localResult.amount;
    if (resolvedAmount == null || !isPlausibleAmount(resolvedAmount)) {
      // Nothing usable was extracted either locally or via AI — there is no
      // transaction to record. This mirrors the previous "silently skip"
      // behavior for genuinely unparseable content, which is correct: an
      // absent amount is not a financial event, not a transaction to lose.
      await _markProcessed(fingerprint, prefs);
      if (aiParsed == null && !localResult.isHighConfidence) {
        await NotificationService.showSmsErrorNotification(
            'Could not parse transaction from SMS.');
      }
      return;
    }
    if (!isPlausibleTransactionDate(txDate)) {
      await _markProcessed(fingerprint, prefs);
      await NotificationService.showSmsErrorNotification(
          'SMS auto-detect error: transaction date is invalid.');
      return;
    }

    final resolvedDirection = aiParsed?.parsed.type ?? localResult.direction;
    final txType = resolvedDirection == 'credit' || resolvedDirection == 'income'
        ? tx_model.TransactionType.income
        : tx_model.TransactionType.expense;

    final resolvedAccountId = aiParsed?.parsed.accountId ??
        localResult.matchedAccountId ??
        (accounts.isNotEmpty ? accounts.first.id : null);
    final resolvedPaymentModeId =
        aiParsed?.parsed.paymentModeId ?? localResult.matchedPaymentModeId;

    final resolvedMode = resolvedPaymentModeId != null
        ? paymentModes.where((m) => m.id == resolvedPaymentModeId).firstOrNull
        : null;
    final affectsBalance = resolvedMode?.type.affectsAccountBalance ?? true;

    final txnCategory = _resolveTxnCategory(localResult.txnCategoryHint, txType);
    final linkedCreditCardAccount = resolvedMode?.type == PaymentModeType.creditCard
        ? creditCardAccounts.where((c) => c.paymentModeId == resolvedMode!.id).firstOrNull
        : null;

    final categories = await firestoreService.watchCategories(uid).first;
    final slug = aiParsed?.parsed.suggestedCategorySlug;
    final category = await resolveOrCreateCategory(
      slug: slug,
      categories: categories,
      uid: uid,
      firestoreService: firestoreService,
    );

    final title = aiParsed?.parsed.title ??
        localResult.merchantCandidate ??
        'Transaction';

    // Offline-first: this transaction is created regardless of whether AI
    // ran/succeeded. processingStatus records how it got here so the UI can
    // surface a review prompt for anything not locally high-confidence —
    // never a silent drop, unlike the pre-refactor "return null" path.
    final processingStatus = localResult.isHighConfidence
        ? tx_model.TxnProcessingStatus.confirmed
        : (aiParsed != null
            ? tx_model.TxnProcessingStatus.aiProcessed
            : tx_model.TxnProcessingStatus.needsAiReview);

    final now = DateTime.now();
    final transaction = tx_model.Transaction(
      id: '',
      userId: uid,
      title: title,
      amount: resolvedAmount,
      type: txType,
      date: txDate,
      categoryId: category.id,
      accountId: resolvedAccountId ?? '',
      paymentModeId: resolvedPaymentModeId,
      source: tx_model.TransactionSource.sms,
      // Once a transaction reaches `confirmed` (here: local parsing was
      // high-confidence enough to skip review entirely), the raw SMS has
      // served its purpose and sensitive digit-runs are redacted before
      // ever being written to Firestore — not stored raw and cleaned up
      // later. Anything not yet confirmed keeps the full text so the
      // review UI can still show "why did the app extract this?".
      rawSms: processingStatus == tx_model.TxnProcessingStatus.confirmed
          ? redactSensitiveDigits(body)
          : body,
      createdAt: now,
      affectsBalance: affectsBalance,
      merchantConfidence: localResult.isHighConfidence ? localResult.confidence : null,
      txnCategory: txnCategory,
      paymentMethod: tx_model.TxnPaymentMethodExt.fromString(localResult.paymentMethod),
      sourceMessageId: fingerprint,
      sourceMessageHash: sourceMessageHash,
      externalTransactionId: localResult.referenceNumber,
      transactionAt: txDate,
      processingStatus: processingStatus,
      aiConfidence: aiParsed?.parsed.confidence,
      aiModel: aiParsed != null ? AppConstants.claudeSmsFastModel : null,
      creditCardAccountId: linkedCreditCardAccount?.id,
    );

    // Mark processed before writing to Firestore so a concurrent isolate
    // won't pass the dedup check and create a duplicate transaction.
    await _markProcessed(fingerprint, prefs);
    if (smsTimestamp != null) {
      final last = prefs.getInt(AppConstants.prefKeyLastSmsTimestamp) ?? 0;
      if (smsTimestamp > last) {
        await prefs.setInt(AppConstants.prefKeyLastSmsTimestamp, smsTimestamp);
      }
    }

    final adjustments = <BalanceAdjustment>[];
    if (resolvedAccountId != null && affectsBalance) {
      final delta = txType == tx_model.TransactionType.income
          ? resolvedAmount
          : -resolvedAmount;
      adjustments.add(BalanceAdjustment(accountId: resolvedAccountId, delta: delta));
    }

    // Credit-card purchases grow outstanding; bill payments shrink it. This
    // never double-counts against the bank balance, since affectsBalance is
    // already false for the creditCard payment mode on the purchase leg —
    // a payment, on the other hand, genuinely does debit the paying bank
    // account (captured above via affectsBalance/resolvedAccountId) while
    // separately reducing the card's own outstanding here.
    final creditCardAdjustments = <CreditCardAdjustment>[];
    if (linkedCreditCardAccount != null) {
      if (txnCategory == tx_model.TxnCategory.creditCardPurchase) {
        creditCardAdjustments.add(CreditCardAdjustment(
            creditCardAccountId: linkedCreditCardAccount.id, delta: resolvedAmount));
      } else if (txnCategory == tx_model.TxnCategory.creditCardPayment) {
        creditCardAdjustments.add(CreditCardAdjustment(
            creditCardAccountId: linkedCreditCardAccount.id, delta: -resolvedAmount));
      }
    }

    final saved = await firestoreService.createTransactionWithBalanceUpdate(
      transaction,
      balanceAdjustments: adjustments,
      creditCardAdjustments: creditCardAdjustments,
    );

    final currency = accounts.isNotEmpty ? accounts.first.currency : 'INR';
    final reviewSuffix =
        processingStatus == tx_model.TxnProcessingStatus.needsAiReview
            ? ' · Needs review'
            : '';
    await NotificationService.showTransactionDetectedNotification(
      id: now.millisecondsSinceEpoch ~/ 1000,
      title: NotificationService.buildNotificationTitle(title, resolvedAmount, currency),
      body: 'Auto-detected$reviewSuffix · Tap to review in Ledger',
      transactionId: saved.id,
    );
  } catch (e) {
    await NotificationService.showSmsErrorNotification('SMS auto-detect error: $e');
  }
}

tx_model.TxnCategory _resolveTxnCategory(
    String? txnCategoryHint, tx_model.TransactionType type) {
  final hinted = tx_model.TxnCategoryExt.fromString(txnCategoryHint);
  return hinted ?? tx_model.TxnCategoryExt.fromLegacyType(type);
}

/// Thin wrapper so `aiParsed?.parsed` reads clearly at call sites without
/// repeating null-checks on the underlying [ParsedSmsTransaction].
class ClaudeParsedResult {
  ClaudeParsedResult(this.parsed);
  final ParsedSmsTransaction parsed;
}

class SmsService {
  final Telephony _telephony = Telephony.instance;

  Future<bool> requestPermissions() async {
    final granted = await _telephony.requestPhoneAndSmsPermissions;
    return granted ?? false;
  }

  void startListening() {
    // Background SMS is handled by the native SmsReceiver + WorkManager pipeline
    // (SmsReceiver.kt / SmsProcessingWorker.kt), which works reliably on modern
    // Android without a persistent notification. This callback only fires while
    // the app is in the foreground.
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        backgroundSmsHandler(message);
      },
      listenInBackground: false,
    );
  }
}
