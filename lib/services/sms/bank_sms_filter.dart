class BankSmsFilter {
  // Simple substring keywords — safe because they're long or domain-specific.
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
    'will be deducted',
    'auto debit',
    'auto-debit',
  ];

  // Short / generic tokens that need whole-word matching to avoid false
  // positives (e.g. "umn" in "autumn", "nach" in "spinach").
  static final _wordBoundaryPatterns = [
    RegExp(r'\bnach\b'),
    RegExp(r'\bumn\b'),
    RegExp(r'\bmandate\b'),
  ];

  static bool looksLikeBankSms(String body) {
    final lower = body.toLowerCase();
    return _keywords.any((k) => lower.contains(k)) ||
        _wordBoundaryPatterns.any((p) => p.hasMatch(lower));
  }
}
