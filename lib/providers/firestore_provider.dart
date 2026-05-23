import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase/firestore_service.dart';

final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());
