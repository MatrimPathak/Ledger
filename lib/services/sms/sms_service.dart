import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import '../firebase/firestore_service.dart';
import '../ai/claude_service.dart';
import '../notification/notification_service.dart';
import '../../core/constants/app_constants.dart';
import '../../models/transaction.dart' as tx_model;
import 'bank_sms_filter.dart';

// Top-level background SMS handler — runs in a separate isolate
@pragma('vm:entry-point')
Future<void> backgroundSmsHandler(SmsMessage message) async {
  try {
    final body = message.body ?? '';
    if (!BankSmsFilter.looksLikeBankSms(body)) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConstants.prefKeyAutoDetect) != true) return;

    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await NotificationService.initialize();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firestoreService = FirestoreService();
    final accounts = await firestoreService.fetchAccounts(user.uid);
    final paymentModes = await firestoreService.fetchPaymentModes(user.uid);

    final apiKey = prefs.getString(AppConstants.prefKeyClaudeApiKey) ??
        AppConstants.claudeApiKeyPlaceholder;

    final claudeService = ClaudeService(apiKey);
    final parsed = await claudeService.parseSmsTransaction(
      smsBody: body,
      accounts: accounts,
      paymentModes: paymentModes,
    );

    if (parsed == null) return;

    // Find best matching category
    final categories = await firestoreService.watchCategories(user.uid).first;
    if (categories.isEmpty) return;
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
      userId: user.uid,
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

    await firestoreService.createTransaction(transaction);

    // Update account balance
    if (resolvedAccountId != null) {
      final accountId = resolvedAccountId;
      final delta = txType == tx_model.TransactionType.income
          ? parsed.amount
          : -parsed.amount;
      await firestoreService.updateAccountBalance(user.uid, accountId, delta);
    }

    final currency = accounts.isNotEmpty ? accounts.first.currency : 'INR';
    await NotificationService.showTransactionDetectedNotification(
      id: now.millisecondsSinceEpoch ~/ 1000,
      title: NotificationService.buildNotificationTitle(
          parsed.title, parsed.amount, currency),
      body: 'Auto-detected · Tap to review in Ledger',
      transactionId: transaction.id,
    );
  } catch (_) {
    // Fail silently in background isolate
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
