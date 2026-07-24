import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:calculadora/services/breez_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const walletA =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  const walletB =
      'legal winner thank year wave sausage worth useful legal winner thank yellow';

  test('wallet storage id is stable and separates different mnemonics', () {
    final first = BreezService.walletStorageId(walletA);
    final repeated = BreezService.walletStorageId(walletA);
    final other = BreezService.walletStorageId(walletB);

    expect(first, repeated);
    expect(first, isNot(other));
    expect(first, hasLength(16));
    expect(first, isNot(contains('abandon')));
  });

  group('Breez payment client (offline)', () {
    test('direct preparation trims destination and preserves amount/policy',
        () async {
      final gateway = _FakePaymentGateway(
        parsed: const InputType.url('ignored'),
        directPreparation: _sparkPreparation(fee: 3),
      );
      final client = BreezPaymentClient(
        gateway: gateway,
        createIdempotencyKey: () => 'offline-test-key',
      );

      final prepared = await client.prepare(
        '  spark-address  ',
        amountSats: 1200,
        feePolicy: FeePolicy.feesIncluded,
      );

      expect(gateway.lastPreparedRequest, isNotNull);
      final request = gateway.lastPreparedRequest!;
      expect(request.amount, BigInt.from(1200));
      expect(request.feePolicy, FeePolicy.feesIncluded);
      expect(
        (request.paymentRequest as PaymentRequest_Input).input,
        'spark-address',
      );
      expect(
          (prepared as BreezPreparedDirect).idempotencyKey, 'offline-test-key');
      expect(prepared.feeFor(OnchainConfirmationSpeed.medium), BigInt.from(3));
    });

    test('LNURL requires an amount before any SDK preparation call', () async {
      final gateway = _FakePaymentGateway(parsed: InputType.lnurlPay(_lnurl));
      final client = BreezPaymentClient(
        gateway: gateway,
        createIdempotencyKey: () => 'unused',
      );

      await expectLater(
        client.prepare('lnurl-test'),
        throwsA(isA<ArgumentError>()),
      );
      expect(gateway.lastLnurlPrepareRequest, isNull);
    });

    test('LNURL uses prepareLnurlPay and does not use direct preparation',
        () async {
      final gateway = _FakePaymentGateway(
        parsed: InputType.lnurlPay(_lnurl),
        lnurlPreparation: _lnurlPreparation(fee: 7),
      );
      final client = BreezPaymentClient(
        gateway: gateway,
        createIdempotencyKey: () => 'unused',
      );

      final prepared = await client.prepare('lnurl-test', amountSats: 2500);

      expect(gateway.lastLnurlPrepareRequest?.amount, BigInt.from(2500));
      expect(gateway.lastPreparedRequest, isNull);
      expect(prepared, isA<BreezPreparedLnurl>());
      expect(prepared.isOnchain, isFalse);
      expect(prepared.feeFor(OnchainConfirmationSpeed.fast), BigInt.from(7));
    });

    test('on-chain fee follows the selected confirmation speed', () {
      final prepared = BreezPreparedPayment.direct(
        _onchainPreparation(slow: 11, medium: 22, fast: 33),
        'stable-key',
      );

      expect(prepared.isOnchain, isTrue);
      expect(prepared.feeFor(OnchainConfirmationSpeed.slow), BigInt.from(11));
      expect(prepared.feeFor(OnchainConfirmationSpeed.medium), BigInt.from(22));
      expect(prepared.feeFor(OnchainConfirmationSpeed.fast), BigInt.from(33));
    });

    test('on-chain send forwards speed and the prepared idempotency key',
        () async {
      final gateway = _FakePaymentGateway(
        parsed: const InputType.url('ignored'),
        payment: _completedPayment,
      );
      final client = BreezPaymentClient(
        gateway: gateway,
        createIdempotencyKey: () => 'unused',
      );
      final prepared = BreezPreparedPayment.direct(
        _onchainPreparation(slow: 11, medium: 22, fast: 33),
        'same-key-on-retry',
      );

      final payment = await client.send(
        prepared,
        onchainSpeed: OnchainConfirmationSpeed.fast,
      );

      expect(payment.status, PaymentStatus.completed);
      final request = gateway.lastSendRequest!;
      expect(request.idempotencyKey, 'same-key-on-retry');
      final options = request.options as SendPaymentOptions_BitcoinAddress;
      expect(options.confirmationSpeed, OnchainConfirmationSpeed.fast);
    });

    test('Lightning/Spark send does not attach on-chain options', () async {
      final gateway = _FakePaymentGateway(
        parsed: const InputType.url('ignored'),
        payment: _completedPayment,
      );
      final client = BreezPaymentClient(
        gateway: gateway,
        createIdempotencyKey: () => 'unused',
      );

      await client.send(
        BreezPreparedPayment.direct(_sparkPreparation(fee: 2), 'spark-key'),
      );

      expect(gateway.lastSendRequest?.idempotencyKey, 'spark-key');
      expect(gateway.lastSendRequest?.options, isNull);
    });
  });
}

final _lnurl = LnurlPayRequestDetails(
  callback: 'https://example.com/callback',
  minSendable: BigInt.from(1000),
  maxSendable: BigInt.from(1000000),
  metadataStr: '[]',
  commentAllowed: 0,
  domain: 'example.com',
  url: 'https://example.com/lnurl',
);

final _invoiceDetails = Bolt11InvoiceDetails(
  amountMsat: null,
  description: 'test',
  expiry: BigInt.from(3600),
  invoice: Bolt11Invoice(
    bolt11: 'lnbc-test',
    source: PaymentRequestSource(),
  ),
  minFinalCltvExpiryDelta: BigInt.from(18),
  network: BitcoinNetwork.bitcoin,
  payeePubkey: '02',
  paymentHash: 'hash',
  paymentSecret: 'secret',
  routingHints: [],
  timestamp: BigInt.zero,
);

PrepareLnurlPayResponse _lnurlPreparation({required int fee}) =>
    PrepareLnurlPayResponse(
      amountSats: BigInt.from(2500),
      payRequest: _lnurl,
      feeSats: BigInt.from(fee),
      invoiceDetails: _invoiceDetails,
      feePolicy: FeePolicy.feesExcluded,
    );

PrepareSendPaymentResponse _sparkPreparation({required int fee}) =>
    PrepareSendPaymentResponse(
      paymentMethod: SendPaymentMethod.sparkAddress(
        address: 'spark-test',
        fee: BigInt.from(fee),
      ),
      amount: BigInt.from(1200),
      feePolicy: FeePolicy.feesExcluded,
    );

PrepareSendPaymentResponse _onchainPreparation({
  required int slow,
  required int medium,
  required int fast,
}) =>
    PrepareSendPaymentResponse(
      paymentMethod: SendPaymentMethod.bitcoinAddress(
        address: const BitcoinAddressDetails(
          address: 'bc1qtest',
          network: BitcoinNetwork.bitcoin,
          source: PaymentRequestSource(),
        ),
        feeQuote: SendOnchainFeeQuote(
          id: 'quote',
          expiresAt: BigInt.from(999999),
          speedFast: SendOnchainSpeedFeeQuote(
            userFeeSat: BigInt.from(fast),
            l1BroadcastFeeSat: BigInt.one,
          ),
          speedMedium: SendOnchainSpeedFeeQuote(
            userFeeSat: BigInt.from(medium),
            l1BroadcastFeeSat: BigInt.one,
          ),
          speedSlow: SendOnchainSpeedFeeQuote(
            userFeeSat: BigInt.from(slow),
            l1BroadcastFeeSat: BigInt.one,
          ),
        ),
      ),
      amount: BigInt.from(1000),
      feePolicy: FeePolicy.feesExcluded,
    );

final _completedPayment = Payment(
  id: 'payment-id',
  paymentType: PaymentType.send,
  status: PaymentStatus.completed,
  amount: BigInt.from(1000),
  fees: BigInt.one,
  timestamp: BigInt.zero,
  method: PaymentMethod.spark,
);

class _FakePaymentGateway implements BreezPaymentGateway {
  final InputType parsed;
  final PrepareSendPaymentResponse? directPreparation;
  final PrepareLnurlPayResponse? lnurlPreparation;
  final Payment? _payment;
  Payment get payment => _payment ?? _completedPayment;

  PrepareSendPaymentRequest? lastPreparedRequest;
  PrepareLnurlPayRequest? lastLnurlPrepareRequest;
  SendPaymentRequest? lastSendRequest;

  _FakePaymentGateway({
    required this.parsed,
    this.directPreparation,
    this.lnurlPreparation,
    Payment? payment,
  }) : _payment = payment;

  @override
  Future<InputType> parse(String input) async => parsed;

  @override
  Future<PrepareLnurlPayResponse> prepareLnurlPay(
    PrepareLnurlPayRequest request,
  ) async {
    lastLnurlPrepareRequest = request;
    return lnurlPreparation!;
  }

  @override
  Future<PrepareSendPaymentResponse> prepareSendPayment(
    PrepareSendPaymentRequest request,
  ) async {
    lastPreparedRequest = request;
    return directPreparation!;
  }

  @override
  Future<LnurlPayResponse> lnurlPay(LnurlPayRequest request) async =>
      LnurlPayResponse(payment: payment);

  @override
  Future<SendPaymentResponse> sendPayment(SendPaymentRequest request) async {
    lastSendRequest = request;
    return SendPaymentResponse(payment: payment);
  }
}
