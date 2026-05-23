import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/account.dart';
import 'auth_provider.dart';
import 'firestore_provider.dart';

final accountsProvider = StreamProvider<List<Account>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(firestoreServiceProvider).watchAccounts(user.uid);
});
