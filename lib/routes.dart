/// Central place for named-route strings so screens don't duplicate magic values.
class SatraRoutes {
  SatraRoutes._();

  static const calculator = '/';
  static const splash = '/splash';
  static const pinSetup = '/pin-setup';
  static const walletHome = '/wallet-home';
  static const receive = '/wallet-home/receive';
  static const send = '/wallet-home/send';
  static const escapeConfirmation = '/wallet-home/escape-confirmation';
  static const nfcTransfer = '/wallet-home/nfc-transfer';
  static const walletBackup = '/wallet-home/backup';
  static const trustedContacts = '/wallet-home/trusted-contacts';
  static const pendingEscapeRecovery = '/wallet-home/pending-escape-recovery';
}
