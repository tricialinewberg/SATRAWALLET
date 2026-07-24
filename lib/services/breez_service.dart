import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import 'breez_payment_client.dart';

export 'breez_payment_client.dart';

/// Owns the Breez SDK (Spark) connection for the app's lifetime: generating
/// or loading the wallet's mnemonic, connecting, and exposing the handful
/// of operations the UI needs. A single shared instance is used everywhere
/// so the app never holds more than one SDK connection open.
class BreezService {
  BreezService._();
  static final BreezService instance = BreezService._();

  static const _mnemonicKey = 'satra_wallet_mnemonic';
  static const _pendingEscapeMnemonicKey = 'satra_pending_escape_mnemonic';
  static const _escapeWalletMnemonicKey = 'satra_escape_wallet_mnemonic';
  static const _fiatCurrencyKey = 'satra_fiat_currency';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final StreamController<int> _balanceController =
      StreamController<int>.broadcast();
  final StreamController<List<Payment>> _paymentsController =
      StreamController<List<Payment>>.broadcast();
  final StreamController<List<DepositInfo>> _unclaimedDepositsController =
      StreamController<List<DepositInfo>>.broadcast();
  final StreamController<Map<String, double>> _fiatRatesController =
      StreamController<Map<String, double>>.broadcast();

  BreezSdk? _sdk;
  StreamSubscription<SdkEvent>? _eventSubscription;
  Future<void>? _initializing;
  Completer<void>? _walletSwitch;
  Map<String, double> _cachedFiatRates = const {};
  int? _cachedBalanceSats;
  List<Payment>? _cachedPayments;
  BigInt? _lastBitcoinReceiveFeeSats;
  List<DepositInfo> _cachedUnclaimedDeposits = const [];
  bool _refreshRunning = false;
  bool _refreshPending = false;
  bool _fiatRefreshPending = false;

  /// Whether [BreezSdkSparkLib.init] has run. That call wires up the native
  /// flutter_rust_bridge library for the whole process and — unlike
  /// `connect`/[disconnect], which are meant to be cycled per wallet
  /// session (e.g. by [restoreFromMnemonic]) — must only ever happen once;
  /// calling it again throws `Bad state: Should not initialize
  /// flutter_rust_bridge twice`.
  bool _frbInitialized = false;

  /// Emits the wallet balance (in sats) right after connecting, and again
  /// whenever a payment lands or the wallet re-syncs while the app is open.
  Stream<int> get balanceStream => _balanceController.stream;

  /// Most recently fetched balance, so a newly-mounted listener can render
  /// immediately even though [balanceStream] is a broadcast stream.
  int? get cachedBalanceSats => _cachedBalanceSats;

  /// Emits the most recent payments (newest first) right after connecting,
  /// and again whenever a payment lands or the wallet re-syncs.
  Stream<List<Payment>> get paymentsStream => _paymentsController.stream;
  List<Payment>? get cachedPayments =>
      _cachedPayments == null ? null : List.unmodifiable(_cachedPayments!);
  Stream<List<DepositInfo>> get unclaimedDepositsStream =>
      _unclaimedDepositsController.stream;
  Stream<Map<String, double>> get fiatRatesStream =>
      _fiatRatesController.stream;
  List<DepositInfo> get cachedUnclaimedDeposits =>
      List.unmodifiable(_cachedUnclaimedDeposits);
  BigInt? get lastBitcoinReceiveFeeSats => _lastBitcoinReceiveFeeSats;

  bool get isConnected => _sdk != null;

  double? cachedFiatRate(String currencyCode) => _cachedFiatRates[currencyCode];

  /// Connects to the Breez SDK, generating a wallet (mnemonic) on first run
  /// or reconnecting with the stored one otherwise. Safe to call repeatedly
  /// — concurrent/later calls await the same in-flight connection. A failed
  /// attempt is not cached, so the next call retries from scratch.
  Future<void> initialize() async {
    await _waitForWalletSwitch();
    if (_sdk != null) return;
    final inFlight = _initializing;
    if (inFlight != null) return inFlight;
    await _connectWithMnemonic(null);
  }

  /// Connects using [mnemonic], or the stored/generated wallet mnemonic if
  /// null, and records the attempt in [_initializing] the same way
  /// [initialize] does — so a later plain [initialize]/[sendPayment] call
  /// that runs while (or right after) this one is in flight sees it as the
  /// current connection instead of racing to reconnect a second time.
  Future<void> _connectWithMnemonic(String? mnemonic) async {
    final attempt = _doInitialize(mnemonicOverride: mnemonic);
    _initializing = attempt;
    try {
      await attempt;
      _initializing = null;
    } catch (error) {
      _initializing = null;
      // A failed native connect may leave partially initialized resources.
      // Tear them down so the next attempt starts from a known state.
      try {
        await disconnect();
      } catch (cleanupError) {
        debugPrint('[BreezService] cleanup after failed init also failed: '
            '$cleanupError (original error: $error)');
      }
      rethrow;
    }
  }

  Future<void> _doInitialize({String? mnemonicOverride}) async {
    if (!_frbInitialized) {
      await BreezSdkSparkLib.init();
      _frbInitialized = true;
    }

    final mnemonic = mnemonicOverride ?? await _getOrCreateMnemonic();
    final apiKey = AppConfig.requireBreezApiKey();
    final config =
        defaultConfig(network: Network.mainnet).copyWith(apiKey: apiKey);
    final seed = Seed.mnemonic(mnemonic: mnemonic, passphrase: null);
    // When mnemonicOverride is null, _getOrCreateMnemonic already guaranteed
    // this mnemonic IS the stored primary — no second Keystore read needed.
    // When overridden (escape/restore), compare once against the stored value
    // so the legacy-dir migration only runs for the true primary wallet.
    final isStoredPrimary = mnemonicOverride == null ||
        (await _secureStorage.read(key: _mnemonicKey))?.trim() ==
            mnemonic.trim();
    final storageDir =
        await _storageDir(mnemonic, isStoredPrimary: isStoredPrimary);

    final sdk = await connect(
      request:
          ConnectRequest(config: config, seed: seed, storageDir: storageDir),
    );
    _sdk = sdk;

    _eventSubscription = sdk.addEventListener().listen((event) {
      switch (event) {
        case SdkEvent_Synced():
        case SdkEvent_PaymentSucceeded():
        case SdkEvent_PaymentPending():
        case SdkEvent_NewDeposits():
        case SdkEvent_ClaimedDeposits():
          _refreshDataBestEffort(source: event.runtimeType.toString());
          break;
        case SdkEvent_UnclaimedDeposits(:final unclaimedDeposits):
          _cachedUnclaimedDeposits = unclaimedDeposits;
          _unclaimedDepositsController.add(unclaimedDeposits);
          break;
        default:
          break;
      }
    }, onError: (Object error, StackTrace stackTrace) {
      debugPrint('[BreezService] event stream failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    });

    // `connect()` is the connection boundary. Everything below is cached UI
    // data and must never turn an already connected wallet into a connection
    // failure. Each operation logs and recovers independently.
    _refreshDataBestEffort(source: 'initial-connect', includeFiat: true);
  }

  void _refreshDataBestEffort({
    required String source,
    bool includeFiat = false,
  }) {
    _refreshPending = true;
    _fiatRefreshPending |= includeFiat;
    if (_refreshRunning) return;
    unawaited(_drainDataRefreshes(source));
  }

  /// SDK sync/payment events often arrive in short bursts. At most one batch
  /// of native reads runs at a time; events received during it collapse into
  /// one follow-up batch instead of multiplying platform-channel and network
  /// work (and the UI rebuilds caused by their stream emissions).
  Future<void> _drainDataRefreshes(String source) async {
    _refreshRunning = true;
    try {
      while (_refreshPending) {
        _refreshPending = false;
        final includeFiat = _fiatRefreshPending;
        _fiatRefreshPending = false;
        await Future.wait([
          _runBestEffort('balance/$source', _refreshBalance),
          _runBestEffort('payments/$source', _refreshPayments),
          _runBestEffort(
            'unclaimed-deposits/$source',
            _refreshUnclaimedDeposits,
          ),
          if (includeFiat)
            _runBestEffort('fiat-rates/$source', _refreshFiatRates),
        ]);
      }
    } finally {
      _refreshRunning = false;
      // No await occurs between the loop condition and finally, but retain
      // this guard so a future refactor cannot strand a queued refresh.
      if (_refreshPending) {
        _refreshDataBestEffort(source: source);
      }
    }
  }

  Future<void> _runBestEffort(
    String operation,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error, stackTrace) {
      debugPrint('[BreezService] $operation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Discards the current native session and performs a fresh connection.
  /// Used by the UI retry action; unlike [initialize], it never reuses an
  /// already completed or unhealthy session.
  Future<void> reconnect() async {
    final lock = await _acquireWalletSwitch();
    try {
      await disconnect();
      await _connectWithMnemonic(null);
    } finally {
      _releaseWalletSwitch(lock);
    }
  }

  static String walletStorageId(String mnemonic) => crypto.sha256
      .convert(utf8.encode(mnemonic.trim()))
      .toString()
      .substring(0, 16);

  Future<String> _storageDir(String mnemonic,
      {required bool isStoredPrimary}) async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory('${dir.path}/breez-spark-wallets');
    await root.create(recursive: true);
    final target = Directory('${root.path}/${walletStorageId(mnemonic)}');

    // One-time migration from the original single-wallet directory. Only the
    // persisted primary wallet may inherit it; an escape wallet always starts
    // in its own directory.
    final legacy = Directory('${dir.path}/breez-spark');
    if (!await target.exists() && isStoredPrimary && await legacy.exists()) {
      await legacy.rename(target.path);
    } else {
      await target.create(recursive: true);
    }
    return target.path;
  }

  Future<void> _waitForWalletSwitch() async {
    final active = _walletSwitch;
    if (active != null) await active.future;
  }

  Future<Completer<void>> _acquireWalletSwitch() async {
    while (_walletSwitch != null) {
      await _walletSwitch!.future;
    }
    final lock = Completer<void>();
    _walletSwitch = lock;
    return lock;
  }

  void _releaseWalletSwitch(Completer<void> lock) {
    if (identical(_walletSwitch, lock)) {
      _walletSwitch = null;
      lock.complete();
    }
  }

  BreezSdk get _requireSdk {
    final sdk = _sdk;
    if (sdk == null) {
      throw StateError('BreezService.initialize() must complete before use');
    }
    return sdk;
  }

  Future<void> _refreshBalance() async {
    final info = await _requireSdk.getInfo(
        request: const GetInfoRequest(ensureSynced: false));
    final balanceSats = info.balanceSats.toInt();
    _cachedBalanceSats = balanceSats;
    _balanceController.add(balanceSats);
  }

  /// Recent payments, newest first. Kept small — this only backs the
  /// "Transações recentes" summary on the wallet home screen, not a full
  /// history view.
  Future<void> _refreshPayments() async {
    final response = await _requireSdk.listPayments(
      request: const ListPaymentsRequest(limit: 20, sortAscending: false),
    );
    _cachedPayments = List.unmodifiable(response.payments);
    _paymentsController.add(_cachedPayments!);
  }

  Future<void> refreshPayments() async {
    await initialize();
    await _refreshPayments();
  }

  Future<void> _refreshUnclaimedDeposits() async {
    final response = await _requireSdk.listUnclaimedDeposits(
      request: const ListUnclaimedDepositsRequest(),
    );
    _cachedUnclaimedDeposits = response.deposits;
    _unclaimedDepositsController.add(response.deposits);
  }

  Future<Payment> claimDeposit(DepositInfo deposit) async {
    await _waitForWalletSwitch();
    final response = await _requireSdk.claimDeposit(
      request: ClaimDepositRequest(
        txid: deposit.txid,
        vout: deposit.vout,
        maxFee: MaxFee.networkRecommended(
          leewaySatPerVbyte: BigInt.one,
        ),
      ),
    );
    await _refreshUnclaimedDeposits();
    await _refreshBalance();
    await _refreshPayments();
    return response.payment;
  }

  Future<RecommendedFees> getRecommendedOnchainFees() async {
    await _waitForWalletSwitch();
    return _requireSdk.recommendedFees();
  }

  /// Current balance in sats.
  Future<int> getBalance() async {
    await _waitForWalletSwitch();
    final info = await _requireSdk.getInfo(
        request: const GetInfoRequest(ensureSynced: false));
    return info.balanceSats.toInt();
  }

  /// Returns the wallet's Lightning Address, registering one (derived from
  /// the wallet's identity key) the first time it's needed.
  Future<String> getLightningAddress() async {
    await _waitForWalletSwitch();
    final sdk = _requireSdk;
    final existing = await sdk.getLightningAddress();
    if (existing != null) return existing.lightningAddress;

    final info =
        await sdk.getInfo(request: const GetInfoRequest(ensureSynced: false));
    final baseUsername =
        'satra${info.identityPubkey.substring(0, 10).toLowerCase()}';

    final available = await sdk.checkLightningAddressAvailable(
      request: CheckLightningAddressRequest(username: baseUsername),
    );
    final username = available
        ? baseUsername
        : '$baseUsername${DateTime.now().millisecondsSinceEpoch % 1000}';

    final registered = await sdk.registerLightningAddress(
      request: RegisterLightningAddressRequest(
          username: username, description: 'Satra Wallet'),
    );
    return registered.lightningAddress;
  }

  /// Creates a BOLT11 invoice, returned as a raw string ready to be
  /// QR-encoded (e.g. by [ReceiveScreen]). Pass null for [amountSats] to
  /// create an amount-less ("any amount") invoice — the sender decides how
  /// much to pay, e.g. via [sendPayment]'s own `amountSats` (see
  /// [executeEscapeSweep], which needs this to drain a wallet's exact
  /// balance with [FeePolicy.feesIncluded], since a fixed-amount invoice
  /// would reject a payment for less than it demands).
  Future<String> createInvoice(int? amountSats,
      {String description = 'Satra Wallet'}) async {
    await _waitForWalletSwitch();
    final response = await _requireSdk.receivePayment(
      request: ReceivePaymentRequest(
        paymentMethod: ReceivePaymentMethod.bolt11Invoice(
          description: description,
          amountSats: amountSats != null ? BigInt.from(amountSats) : null,
          expirySecs: 3600,
          paymentHash: null,
        ),
      ),
    );
    return response.paymentRequest;
  }

  /// Returns an on-chain Bitcoin deposit address managed by the Spark SDK.
  /// Network confirmations and deposit-claim fees apply.
  Future<String> getBitcoinAddress({bool newAddress = false}) async {
    await initialize();
    final response = await _requireSdk.receivePayment(
      request: ReceivePaymentRequest(
        paymentMethod:
            ReceivePaymentMethod.bitcoinAddress(newAddress: newAddress),
      ),
    );
    _lastBitcoinReceiveFeeSats = response.fee;
    return response.paymentRequest;
  }

  /// Parses a pasted destination (invoice, Lightning/on-chain/Spark
  /// address, LNURL, ...) so the caller can tell what kind of payment it
  /// is — in particular, whether it already carries its own amount or the
  /// user must supply one (see `SendScreen`'s use of this).
  Future<InputType> parseInput(String input) async {
    await initialize();
    return _requireSdk.parse(input: input.trim());
  }

  /// If [parsed] is a Lightning Address or a raw LNURL-pay link, returns
  /// the LNURL pay-request details needed to resolve it into an invoice.
  /// Null for every other destination kind (invoices, on-chain/Spark
  /// addresses, ...), which [sendPayment] sends directly instead.
  static LnurlPayRequestDetails? lnurlPayRequestDetailsFor(InputType parsed) =>
      BreezPreparedPayment.lnurlPayRequestFor(parsed);

  /// Sends a payment to a pasted Lightning invoice or address.
  /// [amountSats] is required for amount-less destinations (e.g. a bare
  /// Lightning Address or an on-chain Bitcoin address) and optional
  /// otherwise (e.g. a fixed-amount invoice).
  ///
  /// Calls [initialize] first — a screen can otherwise reach this before
  /// [WalletHomeScreen]'s own connect call has finished, which used to
  /// throw a [StateError] straight out of [_requireSdk].
  ///
  /// [parsedInput] can be passed if the caller already parsed the
  /// destination (e.g. `SendScreen` does, to show what kind of
  /// destination it is) to avoid parsing it a second time — otherwise
  /// this parses it itself. Either way, a Lightning Address or bare LNURL
  /// link is *not* a payment method `sendPayment` on the SDK accepts
  /// directly (it fails with `SdkError.invalidInput`) — it has to be
  /// resolved into an actual invoice first via `prepareLnurlPay`/`lnurlPay`.
  ///
  /// [feePolicy] only applies to the direct (non-LNURL) path below. Pass
  /// [FeePolicy.feesIncluded] with [amountSats] set to the sender's full
  /// balance to drain a wallet exactly — the network fee is deducted from
  /// [amountSats] instead of being added on top, so the total debited
  /// never exceeds what's available (see [executeEscapeSweep]). This only
  /// makes sense against an amount-less invoice (see [createInvoice]) —
  /// a fixed-amount invoice would reject receiving less than it demands.
  Future<Payment> sendPayment(
    String invoiceOrAddress, {
    int? amountSats,
    InputType? parsedInput,
    FeePolicy? feePolicy,
  }) async {
    final prepared = await preparePayment(
      invoiceOrAddress,
      amountSats: amountSats,
      parsedInput: parsedInput,
      feePolicy: feePolicy,
    );
    return sendPreparedPayment(prepared);
  }

  Future<BreezPreparedPayment> preparePayment(
    String invoiceOrAddress, {
    int? amountSats,
    InputType? parsedInput,
    FeePolicy? feePolicy,
  }) async {
    await initialize();
    await _waitForWalletSwitch();
    return BreezPaymentClient(
      gateway: BreezSdkPaymentGateway(_requireSdk),
      createIdempotencyKey: _newIdempotencyKey,
    ).prepare(
      invoiceOrAddress,
      amountSats: amountSats,
      parsedInput: parsedInput,
      feePolicy: feePolicy,
    );
  }

  Future<Payment> sendPreparedPayment(
    BreezPreparedPayment prepared, {
    OnchainConfirmationSpeed onchainSpeed = OnchainConfirmationSpeed.medium,
  }) async {
    await _waitForWalletSwitch();
    final payment = await BreezPaymentClient(
      gateway: BreezSdkPaymentGateway(_requireSdk),
      createIdempotencyKey: _newIdempotencyKey,
    ).send(prepared, onchainSpeed: onchainSpeed);
    await _refreshBalance();
    await _refreshPayments();
    return payment;
  }

  static String _newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Map<String, double>> _fetchFiatRates() async {
    final response = await _requireSdk.listFiatRates();
    return {
      for (final rate in response.rates)
        rate.coin.trim().toUpperCase(): rate.value,
    };
  }

  Future<void> _refreshFiatRates() async {
    final rates = await _fetchFiatRates();
    if (rates.isEmpty) {
      throw StateError('A Breez retornou uma lista de cotações vazia.');
    }
    _cachedFiatRates = Map.unmodifiable(rates);
    _fiatRatesController.add(_cachedFiatRates);
  }

  /// Re-fetches every available BTC/fiat rate from the SDK's rate feed.
  Future<void> refreshFiatRates() async {
    await initialize();
    await _refreshFiatRates();
  }

  Future<String> getSelectedFiatCurrency() async =>
      await _secureStorage.read(key: _fiatCurrencyKey) ?? 'BRL';

  Future<void> setSelectedFiatCurrency(String currencyCode) =>
      _secureStorage.write(key: _fiatCurrencyKey, value: currencyCode);

  Future<String> _getOrCreateMnemonic() async {
    final existing = await _secureStorage.read(key: _mnemonicKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final mnemonic =
        bip39.generateMnemonic(strength: 128); // 128 bits -> 12 words
    await _secureStorage.write(key: _mnemonicKey, value: mnemonic);
    return mnemonic;
  }

  /// The wallet's 12-word recovery phrase, for display/backup in the
  /// "Traga sua carteira" screen.
  Future<String?> getMnemonic() => _secureStorage.read(key: _mnemonicKey);

  /// Persists [mnemonic] as pending an unconfirmed NFC write.
  ///
  /// Historically this protected a per-escape disposable wallet's funds
  /// while its one-time NFC write was in flight. Since the escape wallet is
  /// now a single FIXED wallet created once during physical-key setup (see
  /// [createEscapeWallet]) and never rewritten on subsequent escapes, this
  /// now protects that SAME setup-time write instead: call it right before
  /// [NfcKeyPasswordSetupScreen] attempts to write the freshly-generated
  /// escape wallet to the tag, and only [clearPendingEscapeMnemonic] once
  /// that write is confirmed via [NfcWriteResult.success]. Either way, the
  /// escape wallet's mnemonic is *also* durably persisted under
  /// [_escapeWalletMnemonicKey] regardless of whether the tag write ever
  /// succeeds — so it's never actually at risk of being lost — but a
  /// failed/unconfirmed write still means the physical tag doesn't yet
  /// reflect it, which is what `PendingEscapeRecoveryScreen` lets the user
  /// retry (or view/copy the words directly as a last resort).
  Future<void> savePendingEscapeMnemonic(String mnemonic) =>
      _secureStorage.write(key: _pendingEscapeMnemonicKey, value: mnemonic);

  /// The pending mnemonic, if a previous NFC write hasn't been confirmed
  /// successful yet. Null once cleared.
  Future<String?> getPendingEscapeMnemonic() =>
      _secureStorage.read(key: _pendingEscapeMnemonicKey);

  /// Clears the pending mnemonic. Call only once the NFC write has been
  /// confirmed successful — never on failure/timeout, since that's the
  /// only remaining signal that the tag doesn't yet match what's stored.
  Future<void> clearPendingEscapeMnemonic() =>
      _secureStorage.delete(key: _pendingEscapeMnemonicKey);

  /// Whether a fixed escape wallet has already been configured (see
  /// [createEscapeWallet]). Callers should confirm with the user before
  /// calling [createEscapeWallet] again if this is true — it overwrites
  /// the existing escape wallet, and any balance still on it becomes
  /// unreachable unless backed up first.
  Future<bool> hasEscapeWallet() async {
    final value = await getEscapeWalletMnemonic();
    return value != null && value.isNotEmpty;
  }

  /// The fixed escape-wallet mnemonic configured during physical-key setup
  /// (see [createEscapeWallet]), or null if none has been set up yet.
  /// [executeEscapeSweep] reads this to know where to sweep funds during a
  /// real escape — entirely from local storage, never by reading the NFC
  /// tag, so a real escape never depends on the tag being physically
  /// present or readable.
  Future<String?> getEscapeWalletMnemonic() =>
      _secureStorage.read(key: _escapeWalletMnemonicKey);

  /// Generates a brand-new mnemonic and persists it as THE fixed escape
  /// wallet, overwriting any previous one. Doesn't connect to it or write
  /// anything to a tag — that's [NfcKeyPasswordSetupScreen]'s job, using
  /// this mnemonic plus [NfcService.writeRecoveryCredential].
  ///
  /// Callers must confirm with the user first if [hasEscapeWallet] is
  /// already true (see that method's doc comment).
  Future<String> createEscapeWallet() async {
    final mnemonic =
        bip39.generateMnemonic(strength: 128); // 128 bits -> 12 words
    await _secureStorage.write(key: _escapeWalletMnemonicKey, value: mnemonic);
    return mnemonic;
  }

  /// Disconnects the current wallet (if any) and reconnects using
  /// [mnemonic] instead, replacing whatever wallet was active before.
  Future<void> restoreFromMnemonic(String mnemonic) async {
    final trimmed = mnemonic.trim();
    if (!bip39.validateMnemonic(trimmed)) {
      throw ArgumentError('Frase de recuperação inválida.');
    }

    final lock = await _acquireWalletSwitch();
    try {
      await disconnect();
      await _secureStorage.write(key: _mnemonicKey, value: trimmed);
      await _connectWithMnemonic(trimmed);
    } finally {
      _releaseWalletSwitch(lock);
    }
  }

  /// Executes the "escape" fund sweep: sends this wallet's entire balance
  /// to the FIXED escape wallet at [escapeWalletMnemonic] (see
  /// [createEscapeWallet]/[getEscapeWalletMnemonic]) — the same one every
  /// time, created once ahead of time during physical-key setup rather
  /// than generated fresh on each escape. That matters because it's what
  /// lets the NFC tag be written once at setup and never touched again:
  /// the escape handler no longer needs to write anything to a tag at the
  /// most time-critical, hardware-dependent moment there is.
  ///
  /// The wallet the PIN opens keeps its own persisted mnemonic and stays
  /// the active connection throughout — it simply ends up with a zero
  /// balance. The swept funds are only reachable by whoever restores from
  /// the physical key (see [restoreFromMnemonic]) written to it at setup
  /// time.
  ///
  /// This SDK only supports one live connection at a time, so getting a
  /// destination on the escape wallet requires briefly disconnecting from
  /// the current wallet, connecting as the escape wallet just long enough
  /// to create a receiving destination, then reconnecting the original
  /// wallet to actually send the payment.
  ///
  /// The destination is a native BOLT11 invoice (via [createInvoice]) paid
  /// through the same direct prepareSendPayment/sendPayment path already
  /// used for regular invoice payments — deliberately NOT the wallet's
  /// Lightning Address via LNURL. On-device testing found that paying a
  /// brand-new wallet's Lightning Address fails with a timeout
  /// (`SdkError.lnurlError` calling `breez.tips/lnurlp/.../invoice`), most
  /// likely because the address isn't immediately queryable on Breez's
  /// LNURL server right after registration. A BOLT11 invoice is generated
  /// locally by the escape wallet's own SDK connection and needs no
  /// external HTTP round-trip to resolve, sidestepping that propagation
  /// delay entirely.
  ///
  /// The invoice is deliberately amount-less: a first attempt fixed it to
  /// the current balance and paid it with that same amount, which failed
  /// with `SdkError.sparkError: ... insufficient funds` — the network fee
  /// has to come from somewhere, and there's no room for it once the
  /// entire balance is already earmarked for the invoice. The SDK has no
  /// separate "send max"/drain call, but [FeePolicy.feesIncluded] on
  /// [sendPayment] does the same job: paired with `amountSats: balance`,
  /// it tells the SDK the fee comes out of that balance rather than being
  /// added on top, so the total ever debited is exactly the balance this
  /// wallet already has. That only works against an amount-less invoice —
  /// a fixed-amount one would reject receiving less than it demands, which
  /// is exactly what `feesIncluded` causes it to receive.
  Future<void> executeEscapeSweep(
      {required String escapeWalletMnemonic}) async {
    final lock = await _acquireWalletSwitch();
    try {
      final balance = (await _requireSdk.getInfo(
        request: const GetInfoRequest(ensureSynced: true),
      ))
          .balanceSats
          .toInt();
      if (balance <= 0) return;
      final originalMnemonic = await _getOrCreateMnemonic();
      await disconnect();
      var reconnectedToOriginal = false;
      try {
        await _connectWithMnemonic(escapeWalletMnemonic);

        // No amountSats: an "any amount" invoice, so paying it with
        // FeePolicy.feesIncluded below can legitimately deliver less than the
        // wallet's balance (balance minus the network fee).
        final invoiceResponse = await _requireSdk.receivePayment(
          request: ReceivePaymentRequest(
            paymentMethod: ReceivePaymentMethod.bolt11Invoice(
              description: 'Satra escape sweep',
              amountSats: null,
              expirySecs: 3600,
              paymentHash: null,
            ),
          ),
        );
        await disconnect();

        await _connectWithMnemonic(originalMnemonic);
        reconnectedToOriginal = true;

        final prepareResponse = await _requireSdk.prepareSendPayment(
          request: PrepareSendPaymentRequest(
            paymentRequest:
                PaymentRequest.input(input: invoiceResponse.paymentRequest),
            amount: BigInt.from(balance),
            feePolicy: FeePolicy.feesIncluded,
          ),
        );
        final sent = await _requireSdk.sendPayment(
          request: SendPaymentRequest(
            prepareResponse: prepareResponse,
            idempotencyKey: _newIdempotencyKey(),
          ),
        );
        if (sent.payment.status != PaymentStatus.completed) {
          throw StateError(
            sent.payment.status == PaymentStatus.pending
                ? 'O pagamento de escape está pendente; confira o histórico antes de tentar novamente.'
                : 'O pagamento de escape falhou.',
          );
        }
      } catch (e) {
        // The SDK only supports one live connection at a time, and the escape
        // sweep flips between two wallets. If anything fails before we
        // reconnect to the original wallet, the singleton would otherwise stay
        // pointed at the escape wallet — so the next session would silently
        // operate on the wrong funds. For a wallet whose threat model is a
        // partner who may seize the phone, that's an unacceptable state.
        // Best-effort recovery back to the original wallet, then rethrow so
        // the caller still sees the original failure.
        if (!reconnectedToOriginal) {
          debugPrint(
              '[BreezService] executeEscapeSweep failed mid-sweep — recovering connection to the original wallet: $e');
          try {
            await disconnect();
            await _connectWithMnemonic(originalMnemonic);
          } catch (recoveryError) {
            debugPrint(
                '[BreezService] executeEscapeSweep recovery ALSO failed — wallet connection is in an inconsistent state: $recoveryError');
          }
        }
        rethrow;
      }
    } finally {
      _releaseWalletSwitch(lock);
    }
  }

  Future<void> disconnect() async {
    final subscription = _eventSubscription;
    final sdk = _sdk;
    _eventSubscription = null;
    _sdk = null;
    _initializing = null;
    try {
      await subscription?.cancel();
    } finally {
      await sdk?.disconnect();
    }
  }
}
