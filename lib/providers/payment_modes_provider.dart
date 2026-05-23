import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/payment_mode.dart';
import 'auth_provider.dart';
import 'firestore_provider.dart';

final paymentModesProvider = StreamProvider<List<PaymentMode>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(firestoreServiceProvider).watchPaymentModes(user.uid);
});
