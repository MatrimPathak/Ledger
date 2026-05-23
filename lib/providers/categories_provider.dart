import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/category.dart';
import 'auth_provider.dart';
import 'firestore_provider.dart';

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(firestoreServiceProvider).watchCategories(user.uid);
});
