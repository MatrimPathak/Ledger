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
    'e-mandate',
    'emandate',
    'mandate',
    'nach',
    'umn',
    'will be deducted',
    'auto debit',
    'auto-debit',
  ];

  static bool looksLikeBankSms(String body) {
    final lower = body.toLowerCase();
    return _keywords.any((k) => lower.contains(k));
  }
}
