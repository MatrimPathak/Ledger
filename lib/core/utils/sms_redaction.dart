/// Masks digit runs of 6+ characters (account numbers, balance figures)
/// that appear near account/balance keywords. Used both to minimize what a
/// medium-confidence AI fallback request transmits, and to redact a bank
/// SMS's stored `rawSms` once its transaction reaches
/// `TxnProcessingStatus.confirmed` — after that point the original text has
/// served its "why did the app extract this?" purpose and the sensitive
/// figures no longer need to stay in plaintext. Short last-4-digit
/// card/account references (already masked with "XX" by the bank) are left
/// visible since they carry little exposure on their own and can help
/// disambiguate the instrument.
String redactSensitiveDigits(String smsBody) {
  final keywordProximity = RegExp(
    r'((?:a\/?c|acct|account|bal(?:ance)?)[^\d]{0,15})([0-9,]{6,})',
    caseSensitive: false,
  );
  return smsBody.replaceAllMapped(
    keywordProximity,
    (m) => '${m.group(1)}${'•' * (m.group(2)?.length ?? 6)}',
  );
}
