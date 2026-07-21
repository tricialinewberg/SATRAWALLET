import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

import 'nfc_credential_crypto.dart';

/// Outcome of a [NfcService.writeRecoveryCredential] attempt. A typed result
/// instead of exceptions/booleans so callers can show a specific message —
/// see `NfcKeyPasswordSetupScreen` (the write, at setup time) and
/// `PendingEscapeRecoveryScreen` (retrying it).
enum NfcWriteResult {
  /// The encrypted credential was written AND a read-back+decrypt of the
  /// tag afterward reproduced the original mnemonic exactly.
  success,

  /// No NFC hardware, or NFC is turned off in system settings.
  unavailable,

  /// Writing NDEF tags from a third-party app is not supported on this
  /// platform. Always returned immediately on iOS — see the class doc.
  writeNotSupportedOnPlatform,

  /// A tag was found but rejected the write (locked/read-only, not an NDEF
  /// tag, or the message doesn't fit in its capacity).
  tagNotWritable,

  /// No tag was presented within the timeout.
  timedOut,

  /// The write itself reported success, but re-reading and decrypting the
  /// tag right afterward didn't reproduce the original mnemonic — either
  /// the tag wasn't re-presented in time for the verification read, or it
  /// genuinely didn't retain what was written. Treated the same as any
  /// other non-success: the caller must NOT treat the credential as safely
  /// on the tag.
  verificationFailed,

  /// Any other failure (session error, transceive failure, encryption
  /// error, ...).
  failed,
}

/// Owns NFC read/write for the physical recovery key: encrypting the
/// wallet's mnemonic into a versioned envelope (see [NfcCredentialCrypto])
/// before writing it to a tag as an NDEF text record, and reading it back.
/// The mnemonic itself is never written to a tag in plaintext.
///
/// ## Platform limitation: writing is Android-only
///
/// Apple does not let third-party apps write arbitrary NDEF tags the way
/// Android's reader-mode API does — Core NFC's write path is reserved for a
/// narrow set of tag/entitlement combinations most consumer NTAG-style
/// keys don't satisfy in practice. [writeRecoveryCredential] reflects this
/// by returning [NfcWriteResult.writeNotSupportedOnPlatform] immediately on
/// iOS, without opening a session that would likely fail or hang. Reading
/// (via [startListeningForKey]) works on both platforms.
///
/// ## "Any moment" is really "while the app is open"
///
/// Neither platform offers true always-on background NFC to a closed app.
/// [startListeningForKey] uses Android's foreground-dispatch reader mode
/// and iOS's `NFCTagReaderSession` — both require Satra Wallet to be the
/// active foreground app. So "encostar a chave em qualquer momento" only
/// holds while some Satra Wallet screen that started listening (e.g.
/// [NfcTransferScreen]) is on screen — not while the app is backgrounded
/// or not running. Android additionally keeps discovering tags for as long
/// as the session stays open (tap after tap); iOS closes its session after
/// the first tag by default, matching the one-key-one-detection use case
/// here.
class NfcService {
  NfcService._();
  static final NfcService instance = NfcService._();

  static const _writeTimeout = Duration(seconds: 20);

  /// Timeout for the read-back verification pass that follows a write.
  /// Shorter than [_writeTimeout] since the tag is (usually) still resting
  /// against the phone right after the write completes.
  static const _verifyReadTimeout = Duration(seconds: 12);

  /// Brief pause between closing the write session and opening the
  /// verification read session, so the platform has a moment to fully
  /// release the NFC field before a new session claims it.
  static const _interSessionPause = Duration(milliseconds: 300);

  static const _pollingOptions = {
    NfcPollingOption.iso14443,
    NfcPollingOption.iso15693,
    NfcPollingOption.iso18092,
  };

  bool _sessionActive = false;

  /// Whether NFC can be used right now (hardware present and enabled).
  Future<bool> isAvailable() async {
    final availability = await NfcManager.instance.checkAvailability();
    return availability == NfcAvailability.enabled;
  }

  /// Encrypts [mnemonic] with [password] (see [NfcCredentialCrypto]) and
  /// writes the resulting envelope to the next tag presented as a single
  /// NDEF text record. Then closes that session, opens a NEW session,
  /// waits for the tag again, reads it back, and decrypts it with the same
  /// password — [NfcWriteResult.success] is only returned if that
  /// round-trip reproduces [mnemonic] exactly. The plaintext mnemonic is
  /// never written to the tag.
  ///
  /// Never throws — every failure mode (including a failed verification)
  /// is reported through the returned [NfcWriteResult]. Returns
  /// [NfcWriteResult.failed] immediately if a session is already active,
  /// rather than starting a second, conflicting one.
  Future<NfcWriteResult> writeRecoveryCredential(
    String mnemonic, {
    required String password,
    Duration timeout = _writeTimeout,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return NfcWriteResult.writeNotSupportedOnPlatform;
    }
    if (_sessionActive) return NfcWriteResult.failed;
    if (!await isAvailable()) return NfcWriteResult.unavailable;

    final String envelopeJson;
    try {
      envelopeJson = await NfcCredentialCrypto.encrypt(mnemonic: mnemonic, password: password);
    } catch (_) {
      return NfcWriteResult.failed;
    }

    final writeResult = await _writeOnce(envelopeJson, timeout);
    if (writeResult != NfcWriteResult.success) return writeResult;

    await Future.delayed(_interSessionPause);

    final readBack = await _readOnce(_verifyReadTimeout);
    if (readBack == null) return NfcWriteResult.verificationFailed;

    try {
      final decrypted = await NfcCredentialCrypto.decrypt(envelopeJson: readBack, password: password);
      return decrypted == mnemonic ? NfcWriteResult.success : NfcWriteResult.verificationFailed;
    } catch (_) {
      return NfcWriteResult.verificationFailed;
    }
  }

  Future<NfcWriteResult> _writeOnce(String text, Duration timeout) async {
    final completer = Completer<NfcWriteResult>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(NfcWriteResult.timedOut);
    });

    try {
      _sessionActive = true;
      await NfcManager.instance.startSession(
        pollingOptions: _pollingOptions,
        onDiscovered: (tag) async {
          if (completer.isCompleted) return;
          try {
            final ndef = Ndef.from(tag);
            final message = _encodeTextRecord(text);
            if (ndef == null || !ndef.isWritable || message.byteLength > ndef.maxSize) {
              completer.complete(NfcWriteResult.tagNotWritable);
              return;
            }
            await ndef.write(message: message);
            completer.complete(NfcWriteResult.success);
          } catch (_) {
            if (!completer.isCompleted) completer.complete(NfcWriteResult.failed);
          }
        },
      );
      return await completer.future;
    } catch (_) {
      return NfcWriteResult.failed;
    } finally {
      timer.cancel();
      _sessionActive = false;
      await _stopSessionQuietly();
    }
  }

  /// Waits for a tag and returns the raw NDEF text on it, or null on
  /// timeout/error/no-readable-record. Used both by the write-then-verify
  /// step above and by [startListeningForKey].
  Future<String?> _readOnce(Duration timeout) async {
    final completer = Completer<String?>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });

    try {
      _sessionActive = true;
      await NfcManager.instance.startSession(
        pollingOptions: _pollingOptions,
        onDiscovered: (tag) async {
          if (completer.isCompleted) return;
          try {
            final ndef = Ndef.from(tag);
            final message = ndef == null ? null : await ndef.read();
            final text = message == null ? null : _decodeTextRecord(message);
            completer.complete(text);
          } catch (_) {
            if (!completer.isCompleted) completer.complete(null);
          }
        },
      );
      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      timer.cancel();
      _sessionActive = false;
      await _stopSessionQuietly();
    }
  }

  /// Starts listening for a tag carrying a previously-written recovery
  /// credential envelope. When one is found and its shape is recognized
  /// (see [NfcCredentialCrypto.isRecognizedEnvelope] — version,
  /// walletType, network, well-formed fields) [onCredentialDetected] is
  /// called with the raw envelope JSON and listening stops. This does NOT
  /// decrypt anything — that needs a password only the caller's UI can ask
  /// for (see `NfcTransferScreen`).
  ///
  /// [onError] is called (without stopping Android's session — the user
  /// can just tap again) whenever a discovered tag isn't a readable,
  /// recognized Satra key.
  ///
  /// Returns immediately via [onError] if a session is already active,
  /// rather than starting a second, conflicting one.
  Future<void> startListeningForKey({
    required void Function(String envelopeJson) onCredentialDetected,
    void Function()? onError,
  }) async {
    if (_sessionActive) {
      onError?.call();
      return;
    }
    if (!await isAvailable()) {
      onError?.call();
      return;
    }

    _sessionActive = true;
    try {
      await NfcManager.instance.startSession(
        pollingOptions: _pollingOptions,
        onDiscovered: (tag) async {
          try {
            final ndef = Ndef.from(tag);
            final message = ndef == null ? null : await ndef.read();
            final text = message == null ? null : _decodeTextRecord(message);
            if (text == null || !NfcCredentialCrypto.isRecognizedEnvelope(text)) {
              onError?.call();
              return;
            }
            await stopListening();
            onCredentialDetected(text);
          } catch (_) {
            onError?.call();
          }
        },
      );
    } catch (_) {
      _sessionActive = false;
      onError?.call();
    }
  }

  Future<void> stopListening() async {
    if (!_sessionActive) return;
    _sessionActive = false;
    await _stopSessionQuietly();
  }

  Future<void> _stopSessionQuietly() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {
      // No active session to stop, or the platform channel already tore
      // it down — either way there's nothing left to clean up.
    }
  }

  /// Encodes [text] as a single well-known NDEF Text record (NFC Forum
  /// RTD Text), always as UTF-8 with the "en" language code.
  static NdefMessage _encodeTextRecord(String text) {
    const languageCode = 'en';
    final languageCodeBytes = ascii.encode(languageCode);
    final textBytes = utf8.encode(text);
    final statusByte = languageCodeBytes.length & 0x3F; // high bit 0 = UTF-8
    final payload = Uint8List.fromList([statusByte, ...languageCodeBytes, ...textBytes]);
    final record = NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList(ascii.encode('T')),
      identifier: Uint8List(0),
      payload: payload,
    );
    return NdefMessage(records: [record]);
  }

  /// Decodes the first well-known Text record found in [message]. Returns
  /// null if there isn't one, or if it's UTF-16 (this service never writes
  /// UTF-16, so a UTF-16 record means the tag holds something Satra Wallet
  /// didn't write).
  static String? _decodeTextRecord(NdefMessage message) {
    for (final record in message.records) {
      final isTextRecord = record.typeNameFormat == TypeNameFormat.wellKnown &&
          record.type.length == 1 &&
          record.type[0] == 0x54; // ASCII 'T'
      if (!isTextRecord || record.payload.isEmpty) continue;

      final statusByte = record.payload[0];
      final isUtf16 = (statusByte & 0x80) != 0;
      if (isUtf16) return null;

      final languageCodeLength = statusByte & 0x3F;
      final textStart = 1 + languageCodeLength;
      if (textStart > record.payload.length) continue;

      try {
        return utf8.decode(record.payload.sublist(textStart));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
