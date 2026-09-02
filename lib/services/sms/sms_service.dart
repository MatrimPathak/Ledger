import 'dart:async';
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
import '../../models/sms_template.dart';
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
//
// [isManualSync] is set only by SmsService.syncMissedSms (the "pull to
// refresh" catch-up scan). It changes three things, all in service of
// retrying a message the live path never turned into a transaction,
// rather than treating "we looked at this once" as "this is handled":
//  - the auto-detect toggle and the last-processed watermark are ignored,
//    since a deliberate manual sync should work regardless of live
//    settings and should be able to look further back than "since last
//    time";
//  - the device-local fingerprint "already processed" flag is ignored —
//    it's set even when a message was attempted and produced nothing
//    (ambiguous parse, a transient AI failure), so trusting it here
//    would make those permanently unrecoverable. The Firestore-side
//    hash/reference existence checks further down are the real dedup
//    authority for this path: they only skip a message that actually
//    has a transaction.
//  - per-message notifications are suppressed (a 20-message catch-up
//    firing 20 "processing…" toasts is noise); the caller shows one
//    summary instead.
//
// Returns an [SmsHandlerOutcome] describing what happened, so callers can
// count results — the live path (isManualSync: false) ignores the return
// value. `created` is the only outcome that produced a transaction;
// `skipped` covers every deliberate no-op (not a bank SMS, already handled,
// nothing usable extracted); `failed` means the attempt threw partway
// through — distinct from `skipped` so a caller like
// SmsService.syncMissedSms can tell "nothing new to do" apart from
// "something went wrong".
enum SmsHandlerOutcome { created, skipped, failed }

@pragma('vm:entry-point')
Future<SmsHandlerOutcome> backgroundSmsHandler(
  SmsMessage message, {
  bool isManualSync = false,
}) async {
  final body = message.body ?? '';
  if (!await BankSmsFilter.looksLikeBankSms(body)) return SmsHandlerOutcome.skipped;

  final prefs = await SharedPreferences.getInstance();
  if (!isManualSync && prefs.getBool(AppConstants.prefKeyAutoDetect) != true) {
    return SmsHandlerOutcome.skipped;
  }

  // Timestamp watermark: skip if already processed via catch-up. Manual
  // sync deliberately ignores this — it exists to look further back.
  final smsTimestamp = message.date;
  if (!isManualSync && smsTimestamp != null) {
    final lastProcessed = prefs.getInt(AppConstants.prefKeyLastSmsTimestamp) ?? 0;
    if (smsTimestamp <= lastProcessed) return SmsHandlerOutcome.skipped;
  }

  // Fingerprint dedup: handles null-date messages and concurrent isolate
  // races. Manual sync skips this — see the function doc comment above.
  final fingerprint = _smsFingerprint(message);
  if (!isManualSync && _isAlreadyProcessed(fingerprint, prefs)) return SmsHandlerOutcome.skipped;

  // E-mandate / NACH pre-debit notifications are not real transactions — the
  // actual debit arrives as a separate SMS. Skip them entirely so they never
  // appear in the transaction list.
  if (_isPreDebitNotification(body)) {
    await _markProcessed(fingerprint, prefs);
    return SmsHandlerOutcome.skipped;
  }

  // Honour the user's notification preference in the background isolate.
  NotificationService.notificationsEnabled =
      !isManualSync && (prefs.getBool(AppConstants.prefKeyNotifications) ?? true);

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Already initialized in the main isolate — safe to continue
  }

  await NotificationService.initialize();
  if (!isManualSync) await NotificationService.showProcessingNotification();

  try {
    final uid = resolveBackgroundSmsUid(
      firebaseAuthUid: FirebaseAuth.instance.currentUser?.uid,
      prefs: prefs,
    );
    if (uid == null || uid.isEmpty) {
      if (!isManualSync) {
        await NotificationService.showSmsErrorNotification('Not signed in — open Ledger once to re-authenticate.');
      }
      return SmsHandlerOutcome.skipped;
    }

    final firestoreService = FirestoreService();
    final accounts = await firestoreService.fetchAccounts(uid);
    final paymentModes = await firestoreService.fetchPaymentModes(uid);
    final creditCardAccounts = await firestoreService.fetchCreditCardAccounts(uid);
    // Shared library of shapes learned from any user's past AI-parsed SMS
    // — see ClaudeService.parseSmsTransaction. Fetched fresh per SMS
    // rather than cached process-wide, since a background isolate is
    // typically short-lived anyway and this keeps the match set current.
    // This is a pure optimization (skip an AI call for a shape already
    // learned) — never let it take down the whole handler. A permission
    // error here (e.g. firestore.rules for smsTemplates not yet deployed
    // to this project) must degrade to "no templates available" rather
    // than aborting every SMS, static-rule matches included.
    List<SmsTemplate> smsTemplates;
    try {
      smsTemplates = await firestoreService.fetchSmsTemplates();
    } catch (_) {
      smsTemplates = const [];
    }

    final txDate = smsTimestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(smsTimestamp)
        : DateTime.now();
    final sourceMessageHash = computeSmsHash(body);

    // Layer 2/3: deterministic local parsing + confidence scoring, then a
    // learned-template match for shapes no static rule covers yet.
    final parser = await LocalSmsParser.load();
    final localResult = parser.parse(
      body,
      sender: message.address,
      accounts: accounts,
      paymentModes: paymentModes,
      templates: smsTemplates,
    );
    final matchedTemplateId = localResult.matchedTemplateId;
    if (matchedTemplateId != null) {
      // Fire-and-forget health signal — never block/fail transaction
      // creation over an analytics increment.
      unawaited(firestoreService.recordSmsTemplateMatch(matchedTemplateId));
    }

    // Firestore-side dedup, on top of the device-local fingerprint above —
    // catches the case where app data was cleared/reinstalled and the
    // fingerprint list was lost, but the transaction already exists.
    if (localResult.referenceNumber != null) {
      final exists = await firestoreService.transactionExistsByExternalRef(
          uid, localResult.referenceNumber!);
      if (exists) {
        await _markProcessed(fingerprint, prefs);
        return SmsHandlerOutcome.skipped;
      }
    } else {
      final exists = await firestoreService.transactionExistsByHashNearby(
          uid, sourceMessageHash, txDate);
      if (exists) {
        await _markProcessed(fingerprint, prefs);
        return SmsHandlerOutcome.skipped;
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
                sender: message.address,
              );
        if (parsed != null) {
          aiParsed = ClaudeParsedResult(parsed);
          final learnedTemplate = parsed.learnedTemplate;
          if (learnedTemplate != null) {
            // Publish to the shared library so the next SMS of this exact
            // shape — this user's or any other's — matches locally, no AI
            // call needed. Already passed self-consistency validation in
            // ClaudeService; a failure here is a transient Firestore issue,
            // not a reason to lose the transaction itself.
            unawaited(firestoreService.upsertSmsTemplate(learnedTemplate));
          }
        }
      }
    }

    // ParsedSmsTransaction.amount is non-nullable and defaults to 0.0 when
    // Claude's response omits it — falling straight through to `??` would
    // never reach localResult.amount in that case, discarding a perfectly
    // good local extraction. Only trust the AI amount when it's plausible.
    final aiAmount = aiParsed?.parsed.amount;
    final resolvedAmount = (aiAmount != null && isPlausibleAmount(aiAmount))
        ? aiAmount
        : localResult.amount;
    if (resolvedAmount == null || !isPlausibleAmount(resolvedAmount)) {
      // Nothing usable was extracted either locally or via AI — there is no
      // transaction to record. This mirrors the previous "silently skip"
      // behavior for genuinely unparseable content, which is correct: an
      // absent amount is not a financial event, not a transaction to lose.
      await _markProcessed(fingerprint, prefs);
      if (!isManualSync && aiParsed == null && !localResult.isHighConfidence) {
        await NotificationService.showSmsErrorNotification(
            'Could not parse transaction from SMS.');
      }
      return SmsHandlerOutcome.skipped;
    }
    if (!isPlausibleTransactionDate(txDate)) {
      await _markProcessed(fingerprint, prefs);
      if (!isManualSync) {
        await NotificationService.showSmsErrorNotification(
            'SMS auto-detect error: transaction date is invalid.');
      }
      return SmsHandlerOutcome.skipped;
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
      // localResult.confidence scores the *whole* parse (amount, direction,
      // reference number, instrument match, payment method, merchant
      // together) — only meaningful as a merchant-confidence signal when a
      // merchant candidate was actually found.
      merchantConfidence: (localResult.isHighConfidence &&
              localResult.merchantCandidate != null)
          ? localResult.confidence
          : null,
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

    // Mark processed (and advance the watermark) only after the write
    // actually commits — marking first meant a failed write silently lost
    // the transaction forever, since the dedup guards would then reject
    // every retry of the same SMS. The Firestore-side dedup checks earlier
    // in this function already prevent a genuine duplicate write from a
    // concurrent isolate in the narrow window this reordering reopens.
    await _markProcessed(fingerprint, prefs);
    if (smsTimestamp != null) {
      final last = prefs.getInt(AppConstants.prefKeyLastSmsTimestamp) ?? 0;
      if (smsTimestamp > last) {
        await prefs.setInt(AppConstants.prefKeyLastSmsTimestamp, smsTimestamp);
      }
    }

    final currency = accounts.isNotEmpty ? accounts.first.currency : 'INR';
    final reviewSuffix =
        processingStatus == tx_model.TxnProcessingStatus.needsAiReview
            ? ' · Needs review'
            : '';
    if (!isManualSync) {
      await NotificationService.showTransactionDetectedNotification(
        id: now.millisecondsSinceEpoch ~/ 1000,
        title: NotificationService.buildNotificationTitle(title, resolvedAmount, currency),
        body: 'Auto-detected$reviewSuffix · Tap to review in Ledger',
        transactionId: saved.id,
      );
    }
    return SmsHandlerOutcome.created;
  } catch (e) {
    if (!isManualSync) {
      await NotificationService.showSmsErrorNotification('SMS auto-detect error: $e');
    }
    return SmsHandlerOutcome.failed;
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

/// Outcome of [SmsService.syncMissedSms] — what the pull-to-refresh catch-up
/// scan found, for the UI to summarize (e.g. a SnackBar).
class SmsSyncResult {
  const SmsSyncResult({
    required this.scanned,
    required this.created,
    this.failed = 0,
    this.error,
  });

  /// How many bank-like SMS in the scan window were looked at.
  final int scanned;

  /// How many of those actually produced a new transaction.
  final int created;

  /// How many candidates threw while being processed (a transient AI
  /// failure, a Firestore error) rather than being cleanly skipped as
  /// already-handled or unparseable. Lets the caller distinguish "nothing
  /// new to do" from "something went wrong" even when [created] is 0.
  final int failed;

  /// Set only when the scan couldn't run at all (not signed in, inbox
  /// unreadable) — distinct from "scanned some, created none", which is
  /// success with nothing to do.
  final String? error;
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

  /// Pull-to-refresh catch-up: re-scans the SMS inbox for bank-like
  /// messages from the last [lookbackDays] and retries parsing on any that
  /// don't yet have a transaction — including ones the live path already
  /// attempted and failed on (a transient AI error, an ambiguous message
  /// that's since been fixed by a rule/template update). See
  /// backgroundSmsHandler's doc comment for exactly what "manual sync"
  /// changes about its dedup behavior.
  ///
  /// Runs candidates sequentially, not in parallel — each may call the
  /// Claude API, and a burst of concurrent calls against one user's key
  /// serves nobody faster. A message already backed by a transaction is
  /// cheap to re-check (one local parse + one Firestore read, no AI call),
  /// so re-running this repeatedly only pays full cost for messages that
  /// are genuinely still unresolved.
  Future<SmsSyncResult> syncMissedSms({int lookbackDays = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = resolveBackgroundSmsUid(
      firebaseAuthUid: FirebaseAuth.instance.currentUser?.uid,
      prefs: prefs,
    );
    if (uid == null || uid.isEmpty) {
      return const SmsSyncResult(
          scanned: 0, created: 0, error: 'Not signed in.');
    }

    List<SmsMessage> messages;
    try {
      final cutoff = DateTime.now()
          .subtract(Duration(days: lookbackDays))
          .millisecondsSinceEpoch;
      messages = await _telephony.getInboxSms(
        columns: [
          SmsColumn.ADDRESS,
          SmsColumn.BODY,
          SmsColumn.DATE,
          SmsColumn.ID,
        ],
        filter: SmsFilter.where(SmsColumn.DATE).greaterThan(cutoff.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE)],
      );
    } catch (e) {
      return SmsSyncResult(
          scanned: 0, created: 0, error: 'Could not read SMS inbox: $e');
    }

    final candidates = <SmsMessage>[];
    for (final m in messages) {
      if (await BankSmsFilter.looksLikeBankSms(m.body ?? '')) {
        candidates.add(m);
      }
    }

    var created = 0;
    var failed = 0;
    // backgroundSmsHandler sets NotificationService.notificationsEnabled
    // (a process-wide static) to false on every isManualSync call, since a
    // 20-message catch-up firing 20 toasts would be noise — but that flag
    // isn't scoped to this call, so it must be restored once the loop is
    // done or every notification (including for manually added/edited
    // transactions) stays silently suppressed until a live SMS arrives or
    // the app restarts.
    final previousNotificationsEnabled = NotificationService.notificationsEnabled;
    try {
      for (final message in candidates) {
        final outcome =
            await backgroundSmsHandler(message, isManualSync: true);
        switch (outcome) {
          case SmsHandlerOutcome.created:
            created++;
            break;
          case SmsHandlerOutcome.failed:
            failed++;
            break;
          case SmsHandlerOutcome.skipped:
            break;
        }
      }
    } finally {
      NotificationService.notificationsEnabled = previousNotificationsEnabled;
    }

    return SmsSyncResult(
        scanned: candidates.length, created: created, failed: failed);
  }
}
