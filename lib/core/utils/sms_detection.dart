class BankSmsFilter {
  static const _keywords = [
    'debited',
    'credited',
    'debit',
    'credit',
    'inr',
    'upi ref',
    'neft',
    'imps',
    'rtgs',
    'a/c',
    'acct',
    'transaction',
    'rs.',
    'rs ',
    'balance',
    'bank',
  ];

  static bool looksLikeBankSms(String body) {
    final lower = body.toLowerCase();
    return _keywords.any((k) => lower.contains(k));
  }
}

String? resolveBackgroundSmsUid({
  required String? currentUserUid,
  required String? persistedUid,
}) {
  if (currentUserUid != null && currentUserUid.isNotEmpty) {
    return currentUserUid;
  }
  if (persistedUid != null && persistedUid.isNotEmpty) return persistedUid;
  return null;
}
