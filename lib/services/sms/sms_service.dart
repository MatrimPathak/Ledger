import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import '../firebase/firestore_service.dart';
import '../ai/claude_service.dart';
import '../notification/notification_service.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/sms_detection.dart';
import '../../models/transaction.dart' as tx_model;

// Top-level background SMS handler — runs in a separate isolate
@pragma('vm:entry-point')
Future<void> backgroundSmsHandler(SmsMessage message) async {
  final body = message.body ?? '';
  if (!BankSmsFilter.looksLikeBankSms(body)) return;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(AppConstants.prefKeyAutoDetect) != true) return;

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Already initialized in the main isolate — safe to continue
  }

  await NotificationService.initialize();

  // Show a "processing" notification immediately so we know the handler fired.
  // This is replaced by the final transaction notification on success.
  await NotificationService.showProcessingNotification(body);

  try {
    // FirebaseAuth.instance.currentUser is null in a fresh background isolate
    // because auth state is restored asynchronously. Fall back to the uid we
    // persisted in SharedPreferences on the last foreground app start.
    final uid = resolveBackgroundSmsUid(
      currentUserUid: FirebaseAuth.instance.currentUser?.uid,
      persistedUid: prefs.getString(AppConstants.prefKeyUid),
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
    if (categories.isEmpty) {
      await NotificationService.showSmsErrorNotification('No categories found — open Ledger to set up categories.');
      return;
    }

    final slug = parsed.suggestedCategorySlug ?? 'other';
    final category = categories.firstWhere(
      (c) => c.title.toLowerCase().contains(slug),
      orElse: () => categories.last,
    );

    final txType = parsed.type == 'income'
        ? tx_model.TransactionType.income
        : tx_model.TransactionType.expense;

    final now = DateTime.now();
    final resolvedAccountId =
        parsed.accountId ?? (accounts.isNotEmpty ? accounts.first.id : null);

    final transaction = tx_model.Transaction(
      id: '',
      userId: uid,
      title: parsed.title,
      amount: parsed.amount,
      type: txType,
      date: now,
      categoryId: category.id,
      accountId: resolvedAccountId ?? '',
      paymentModeId: parsed.paymentModeId,
      source: tx_model.TransactionSource.sms,
      rawSms: body,
      createdAt: now,
    );

    final saved = await firestoreService.createTransaction(transaction);

    if (resolvedAccountId != null) {
      final delta = txType == tx_model.TransactionType.income
          ? parsed.amount
          : -parsed.amount;
      await firestoreService.updateAccountBalance(uid, resolvedAccountId, delta);
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
}
