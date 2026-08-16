import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/credit_card_account.dart';
import 'auth_provider.dart';
import 'firestore_provider.dart';

final creditCardAccountsProvider =
    StreamProvider<List<CreditCardAccount>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(firestoreServiceProvider).watchCreditCardAccounts(user.uid);
});
