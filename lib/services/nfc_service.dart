import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

/// Outcome of a [NfcService.writeRecoveryCredential] attempt. A typed result
/// instead of exceptions/booleans so callers can show a specific message
/// (or, in the escape flow, silently ignore all of them — see
/// `WalletHomeScreen._writeRecoveryKey`).
enum NfcWriteResult {
  /// The mnemonic was written to the tag.
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

  /// Any other failure (session error, transceive failure, ...).
  failed,
}

/// Owns NFC read/write for the physical recovery key: writing the wallet's
/// mnemonic to a tag as an NDEF text record, and reading it back.
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

  /// Writes [mnemonic] to the next tag presented, as a single NDEF text
  /// record. Stops waiting after [timeout] if no tag is presented.
  ///
  /// Never throws — every failure mode is reported through the returned
  /// [NfcWriteResult].
  Future<NfcWriteResult> writeRecoveryCredential(
    String mnemonic, {
    Duration timeout = _writeTimeout,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return NfcWriteResult.writeNotSupportedOnPlatform;
    }
    if (!await isAvailable()) return NfcWriteResult.unavailable;

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
            final message = _encodeTextRecord(mnemonic);
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

  /// Starts listening for a tag carrying a previously-written recovery
  /// credential. When one is found and successfully decoded,
  /// [onKeyDetected] is called with the mnemonic and listening stops.
  ///
  /// [onError] is called (without stopping Android's session — the user
  /// can just tap again) whenever a discovered tag isn't a readable Satra
  /// key: not NDEF-formatted, empty, or an unrecognized record.
  Future<void> startListeningForKey({
    required void Function(String mnemonic) onKeyDetected,
    void Function()? onError,
  }) async {
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
            final mnemonic = message == null ? null : _decodeTextRecord(message);
            if (mnemonic == null || mnemonic.isEmpty) {
              onError?.call();
              return;
            }
            await stopListening();
            onKeyDetected(mnemonic);
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
