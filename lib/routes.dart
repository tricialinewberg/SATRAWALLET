/// Central place for named-route strings so screens don't duplicate magic values.
class SatraRoutes {
  SatraRoutes._();

  static const calculator = '/';
  static const pinSetup = '/pin-setup';
  static const walletHome = '/wallet-home';
  static const receive = '/wallet-home/receive';
  static const send = '/wallet-home/send';
  static const escapeConfirmation = '/wallet-home/escape-confirmation';
  static const nfcTransfer = '/wallet-home/nfc-transfer';
  static const walletBackup = '/wallet-home/backup';
  static const trustedContacts = '/wallet-home/trusted-contacts';
  static const pendingEscapeRecovery = '/wallet-home/pending-escape-recovery';
  static const nfcKeyPasswordSetup = '/wallet-home/nfc-key-password';
  static const inheritance = '/wallet-home/inheritance';
  static const inheritanceHeirs = '/wallet-home/inheritance/heirs';
  static const inheritancePassword = '/wallet-home/inheritance/password';
  static const inheritancePeriods = '/wallet-home/inheritance/periods';
  static const inheritanceMessageTest = '/wallet-home/inheritance/message-test';
  static const inheritanceClaim = '/inheritance-claim';
  static const support = '/wallet-home/support';
  static const settings = '/wallet-home/settings';
}
