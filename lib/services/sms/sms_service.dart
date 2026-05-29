import 'dart:convert';
import 'package:another_telephony/telephony.dart';
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

// Looks up a category by slug. If none matches, creates one from the default
// category definitions so the user never sees an "Other" fallback silently.
Future<Category> _resolveOrCreateCategory({
  required String slug,
  required List<Category> categories,
  required String uid,
  required FirestoreService firestoreService,
}) async {
  final lower = slug.toLowerCase();
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
  if (!BankSmsFilter.looksLikeBankSms(body)) return;

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

  // Honour the user's notification preference in the background isolate.
  NotificationService.notificationsEnabled =
      prefs.getBool(AppConstants.prefKeyNotifications) ?? true;

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Already initialized in the main isolate — safe to continue
  }

  await NotificationService.initialize();
  await NotificationService.showProcessingNotification(body);

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

    final apiKey = prefs.getString(AppConstants.prefKeyClaudeApiKey) ??
        AppConstants.claudeApiKeyPlaceholder;
    if (apiKey == AppConstants.claudeApiKeyPlaceholder || apiKey.isEmpty) {
      await NotificationService.showSmsErrorNotification('Add your Claude API key in Settings to auto-detect transactions.');
      return;
    }

    final claudeService = ClaudeService(apiKey);
    final parsed = await claudeService.parseSmsTransaction(
      smsBody: body,
      accounts: accounts,
      paymentModes: paymentModes,
    );

    if (parsed == null) {
      await NotificationService.showSmsErrorNotification('Could not parse transaction from SMS (low confidence).');
      return;
    }

    final categories = await firestoreService.watchCategories(uid).first;
    final slug = parsed.suggestedCategorySlug ?? 'other';
    final category = await _resolveOrCreateCategory(
      slug: slug,
      categories: categories,
      uid: uid,
      firestoreService: firestoreService,
    );

    final txType = parsed.type == 'income'
        ? tx_model.TransactionType.income
        : tx_model.TransactionType.expense;

    final txDate = smsTimestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(smsTimestamp)
        : DateTime.now();
    final now = DateTime.now();
    final resolvedAccountId =
        parsed.accountId ?? (accounts.isNotEmpty ? accounts.first.id : null);

    final resolvedMode = parsed.paymentModeId != null
        ? paymentModes.where((m) => m.id == parsed.paymentModeId).firstOrNull
        : null;
    final affectsBalance = resolvedMode?.type.affectsAccountBalance ?? true;

    final transaction = tx_model.Transaction(
      id: '',
      userId: uid,
      title: parsed.title,
      amount: parsed.amount,
      type: txType,
      date: txDate,
      categoryId: category.id,
      accountId: resolvedAccountId ?? '',
      paymentModeId: parsed.paymentModeId,
      source: tx_model.TransactionSource.sms,
      rawSms: body,
      createdAt: now,
      affectsBalance: affectsBalance,
    );

    final saved = await firestoreService.createTransaction(transaction);

    if (resolvedAccountId != null && affectsBalance) {
      final delta = txType == tx_model.TransactionType.income
          ? parsed.amount
          : -parsed.amount;
      await firestoreService.updateAccountBalance(uid, resolvedAccountId, delta);
    }

    await _markProcessed(fingerprint, prefs);
    if (smsTimestamp != null) {
      final last = prefs.getInt(AppConstants.prefKeyLastSmsTimestamp) ?? 0;
      if (smsTimestamp > last) {
        await prefs.setInt(AppConstants.prefKeyLastSmsTimestamp, smsTimestamp);
      }
    }

    final currency = accounts.isNotEmpty ? accounts.first.currency : 'INR';
    await NotificationService.showTransactionDetectedNotification(
      id: now.millisecondsSinceEpoch ~/ 1000,
      title: NotificationService.buildNotificationTitle(parsed.title, parsed.amount, currency),
      body: 'Auto-detected · Tap to review in Ledger',
      transactionId: saved.id,
    );
  } catch (e) {
    await NotificationService.showSmsErrorNotification('SMS auto-detect error: $e');
  }
}

class SmsService {
  final Telephony _telephony = Telephony.instance;

  Future<bool> requestPermissions() async {
    final granted = await _telephony.requestPhoneAndSmsPermissions;
    return granted ?? false;
  }

  void startListening() {
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        backgroundSmsHandler(message);
      },
      listenInBackground: true,
      onBackgroundMessage: backgroundSmsHandler,
    );
  }

  /// Reads the SMS inbox for bank messages that arrived since the last
  /// processed timestamp and creates transactions for any that were missed
  /// while the app was closed. Fetches Firestore data once for all messages
  /// to avoid N×(init + Firestore reads) on startup.
  Future<void> processMissedSms(String uid, SharedPreferences prefs) async {
    final apiKey = prefs.getString(AppConstants.prefKeyClaudeApiKey) ?? '';
    if (apiKey.isEmpty || apiKey == AppConstants.claudeApiKeyPlaceholder) return;

    final lastTimestamp = prefs.getInt(AppConstants.prefKeyLastSmsTimestamp) ?? 0;
    final cutoff = lastTimestamp > 0
        ? lastTimestamp
        : DateTime.now()
            .subtract(const Duration(days: 7))
            .millisecondsSinceEpoch;

    List<SmsMessage> messages;
    try {
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
    } catch (_) {
      return;
    }

    final bankMessages = messages
        .where((m) => BankSmsFilter.looksLikeBankSms(m.body ?? ''))
        .toList();
    if (bankMessages.isEmpty) return;

    // Pre-fetch shared data once for all missed messages.
    final firestoreService = FirestoreService();
    final accounts = await firestoreService.fetchAccounts(uid);
    final paymentModes = await firestoreService.fetchPaymentModes(uid);
    // Use a mutable list so newly auto-created categories are visible to
    // subsequent messages in the same batch (avoids duplicate creation).
    var categories = await firestoreService.watchCategories(uid).first;

    await NotificationService.initialize();
    NotificationService.notificationsEnabled =
        prefs.getBool(AppConstants.prefKeyNotifications) ?? true;

    final claudeService = ClaudeService(apiKey);

    for (final sms in bankMessages) {
      final fingerprint = _smsFingerprint(sms);
      if (_isAlreadyProcessed(fingerprint, prefs)) continue;

      final smsTimestamp = sms.date;
      if (smsTimestamp != null) {
        final last = prefs.getInt(AppConstants.prefKeyLastSmsTimestamp) ?? 0;
        if (smsTimestamp <= last) continue;
      }

      final body = sms.body ?? '';
      try {
        final parsed = await claudeService.parseSmsTransaction(
          smsBody: body,
          accounts: accounts,
          paymentModes: paymentModes,
        );
        if (parsed == null) continue;

        final slug = parsed.suggestedCategorySlug ?? 'other';
        final category = await _resolveOrCreateCategory(
          slug: slug,
          categories: categories,
          uid: uid,
          firestoreService: firestoreService,
        );
        // Keep the local list up-to-date so the next SMS in this batch
        // reuses the just-created category instead of creating it again.
        if (!categories.any((c) => c.id == category.id)) {
          categories = [...categories, category];
        }

        final txType = parsed.type == 'income'
            ? tx_model.TransactionType.income
            : tx_model.TransactionType.expense;
        final txDate = smsTimestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(smsTimestamp)
            : DateTime.now();
        final now = DateTime.now();
        final resolvedAccountId =
            parsed.accountId ?? (accounts.isNotEmpty ? accounts.first.id : null);

        final resolvedMode = parsed.paymentModeId != null
            ? paymentModes.where((m) => m.id == parsed.paymentModeId).firstOrNull
            : null;
        final affectsBalance = resolvedMode?.type.affectsAccountBalance ?? true;

        final transaction = tx_model.Transaction(
          id: '',
          userId: uid,
          title: parsed.title,
          amount: parsed.amount,
          type: txType,
          date: txDate,
          categoryId: category.id,
          accountId: resolvedAccountId ?? '',
          paymentModeId: parsed.paymentModeId,
          source: tx_model.TransactionSource.sms,
          rawSms: body,
          createdAt: now,
          affectsBalance: affectsBalance,
        );

        final saved = await firestoreService.createTransaction(transaction);

        if (resolvedAccountId != null && affectsBalance) {
          final delta = txType == tx_model.TransactionType.income
              ? parsed.amount
              : -parsed.amount;
          await firestoreService.updateAccountBalance(uid, resolvedAccountId, delta);
        }

        await _markProcessed(fingerprint, prefs);
        if (smsTimestamp != null) {
          final last = prefs.getInt(AppConstants.prefKeyLastSmsTimestamp) ?? 0;
          if (smsTimestamp > last) {
            await prefs.setInt(AppConstants.prefKeyLastSmsTimestamp, smsTimestamp);
          }
        }

        final currency = accounts.isNotEmpty ? accounts.first.currency : 'INR';
        await NotificationService.showTransactionDetectedNotification(
          id: now.millisecondsSinceEpoch ~/ 1000,
          title: NotificationService.buildNotificationTitle(
              parsed.title, parsed.amount, currency),
          body: 'Auto-detected · Tap to review in Ledger',
          transactionId: saved.id,
        );
      } catch (_) {
        continue;
      }
    }
  }
}
