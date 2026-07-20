import 'dart:async';
import 'dart:io';

import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Owns the Breez SDK (Spark) connection for the app's lifetime: generating
/// or loading the wallet's mnemonic, connecting, and exposing the handful
/// of operations the UI needs. A single shared instance is used everywhere
/// so the app never holds more than one SDK connection open.
class BreezService {
  BreezService._();
  static final BreezService instance = BreezService._();

  static const _mnemonicKey = 'satra_wallet_mnemonic';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final StreamController<int> _balanceController = StreamController<int>.broadcast();

  BreezSdk? _sdk;
  StreamSubscription<SdkEvent>? _eventSubscription;
  Future<void>? _initializing;
  double? _cachedBrlPerBtc;

  /// Emits the wallet balance (in sats) right after connecting, and again
  /// whenever a payment lands or the wallet re-syncs while the app is open.
  Stream<int> get balanceStream => _balanceController.stream;

  bool get isConnected => _sdk != null;

  double? get cachedBrlPerBtc => _cachedBrlPerBtc;

  /// Connects to the Breez SDK, generating a wallet (mnemonic) on first run
  /// or reconnecting with the stored one otherwise. Safe to call repeatedly
  /// — concurrent/later calls await the same in-flight connection. A failed
  /// attempt is not cached, so the next call retries from scratch.
  Future<void> initialize() async {
    final inFlight = _initializing;
    if (inFlight != null) return inFlight;

    final attempt = _doInitialize();
    _initializing = attempt;
    try {
      await attempt;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  Future<void> _doInitialize() async {
    await BreezSdkSparkLib.init();

    final mnemonic = await _getOrCreateMnemonic();
    final apiKey = dotenv.env['BREEZ_API_KEY'] ?? '';
    final config = defaultConfig(network: Network.mainnet).copyWith(apiKey: apiKey);
    final seed = Seed.mnemonic(mnemonic: mnemonic, passphrase: null);
    final storageDir = await _storageDir();

    _sdk = await connect(
      request: ConnectRequest(config: config, seed: seed, storageDir: storageDir),
    );

    _eventSubscription = _sdk!.addEventListener().listen((event) {
      switch (event) {
        case SdkEvent_Synced():
        case SdkEvent_PaymentSucceeded():
        case SdkEvent_PaymentPending():
        case SdkEvent_NewDeposits():
        case SdkEvent_ClaimedDeposits():
          unawaited(_refreshBalance());
          break;
        default:
          break;
      }
    });

    await _refreshBalance();
    _cachedBrlPerBtc = await _fetchBrlPerBtc();
  }

  Future<String> _storageDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/breez-spark';
    await Directory(path).create(recursive: true);
    return path;
  }

  BreezSdk get _requireSdk {
    final sdk = _sdk;
    if (sdk == null) {
      throw StateError('BreezService.initialize() must complete before use');
    }
    return sdk;
  }

  Future<void> _refreshBalance() async {
    final info = await _requireSdk.getInfo(request: const GetInfoRequest(ensureSynced: false));
    _balanceController.add(info.balanceSats.toInt());
  }

  /// Current balance in sats.
  Future<int> getBalance() async {
    final info = await _requireSdk.getInfo(request: const GetInfoRequest(ensureSynced: false));
    return info.balanceSats.toInt();
  }

  /// Returns the wallet's Lightning Address, registering one (derived from
  /// the wallet's identity key) the first time it's needed.
  Future<String> getLightningAddress() async {
    final sdk = _requireSdk;
    final existing = await sdk.getLightningAddress();
    if (existing != null) return existing.lightningAddress;

    final info = await sdk.getInfo(request: const GetInfoRequest(ensureSynced: false));
    final baseUsername = 'satra${info.identityPubkey.substring(0, 10).toLowerCase()}';

    final available = await sdk.checkLightningAddressAvailable(
      request: CheckLightningAddressRequest(username: baseUsername),
    );
    final username = available ? baseUsername : '$baseUsername${DateTime.now().millisecondsSinceEpoch % 1000}';

    final registered = await sdk.registerLightningAddress(
      request: RegisterLightningAddressRequest(username: username, description: 'Satra Wallet'),
    );
    return registered.lightningAddress;
  }

  /// Creates a BOLT11 invoice for a fixed amount, returned as a raw string
  /// ready to be QR-encoded (e.g. by [ReceiveScreen]).
  Future<String> createInvoice(int amountSats, {String description = 'Satra Wallet'}) async {
    final response = await _requireSdk.receivePayment(
      request: ReceivePaymentRequest(
        paymentMethod: ReceivePaymentMethod.bolt11Invoice(
          description: description,
          amountSats: BigInt.from(amountSats),
          expirySecs: 3600,
          paymentHash: null,
        ),
      ),
    );
    return response.paymentRequest;
  }

  /// Sends a payment to a pasted Lightning invoice or address.
  /// [amountSats] is required for amount-less destinations (e.g. a bare
  /// Lightning Address) and optional otherwise (e.g. a fixed-amount invoice).
  Future<Payment> sendPayment(String invoiceOrAddress, {int? amountSats}) async {
    final sdk = _requireSdk;
    final prepareResponse = await sdk.prepareSendPayment(
      request: PrepareSendPaymentRequest(
        paymentRequest: PaymentRequest.input(input: invoiceOrAddress.trim()),
        amount: amountSats != null ? BigInt.from(amountSats) : null,
      ),
    );
    final response = await sdk.sendPayment(
      request: SendPaymentRequest(prepareResponse: prepareResponse),
    );
    await _refreshBalance();
    return response.payment;
  }

  Future<double?> _fetchBrlPerBtc() async {
    try {
      final response = await _requireSdk.listFiatRates();
      for (final rate in response.rates) {
        if (rate.coin == 'BRL') return rate.value;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Re-fetches the BRL/BTC rate from the SDK's fiat rate feed.
  Future<double?> refreshBrlPerBtc() async {
    _cachedBrlPerBtc = await _fetchBrlPerBtc();
    return _cachedBrlPerBtc;
  }

  Future<String> _getOrCreateMnemonic() async {
    final existing = await _secureStorage.read(key: _mnemonicKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final mnemonic = bip39.generateMnemonic(strength: 128); // 128 bits -> 12 words
    await _secureStorage.write(key: _mnemonicKey, value: mnemonic);
    return mnemonic;
  }

  /// The wallet's 12-word recovery phrase, for display/backup in the
  /// "Traga sua carteira" screen.
  Future<String?> getMnemonic() => _secureStorage.read(key: _mnemonicKey);

  /// Disconnects the current wallet (if any) and reconnects using
  /// [mnemonic] instead, replacing whatever wallet was active before.
  Future<void> restoreFromMnemonic(String mnemonic) async {
    final trimmed = mnemonic.trim();
    if (!bip39.validateMnemonic(trimmed)) {
      throw ArgumentError('Frase de recuperação inválida.');
    }

    await disconnect();
    await _secureStorage.write(key: _mnemonicKey, value: trimmed);
    await initialize();
  }

  Future<void> disconnect() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _sdk?.disconnect();
    _sdk = null;
    _initializing = null;
  }
}
