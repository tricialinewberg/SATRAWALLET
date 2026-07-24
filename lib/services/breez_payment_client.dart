import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';

/// Small boundary around the native Breez SDK payment calls.
///
/// Keeping this interface narrow lets unit tests exercise payment routing,
/// request construction, fees and idempotency without loading Rust, opening
/// a wallet, contacting a relay or spending sats.
abstract interface class BreezPaymentGateway {
  Future<InputType> parse(String input);

  Future<PrepareLnurlPayResponse> prepareLnurlPay(
    PrepareLnurlPayRequest request,
  );

  Future<PrepareSendPaymentResponse> prepareSendPayment(
    PrepareSendPaymentRequest request,
  );

  Future<LnurlPayResponse> lnurlPay(LnurlPayRequest request);

  Future<SendPaymentResponse> sendPayment(SendPaymentRequest request);
}

class BreezSdkPaymentGateway implements BreezPaymentGateway {
  final BreezSdk sdk;

  const BreezSdkPaymentGateway(this.sdk);

  @override
  Future<InputType> parse(String input) => sdk.parse(input: input);

  @override
  Future<PrepareLnurlPayResponse> prepareLnurlPay(
    PrepareLnurlPayRequest request,
  ) =>
      sdk.prepareLnurlPay(request: request);

  @override
  Future<PrepareSendPaymentResponse> prepareSendPayment(
    PrepareSendPaymentRequest request,
  ) =>
      sdk.prepareSendPayment(request: request);

  @override
  Future<LnurlPayResponse> lnurlPay(LnurlPayRequest request) =>
      sdk.lnurlPay(request: request);

  @override
  Future<SendPaymentResponse> sendPayment(SendPaymentRequest request) =>
      sdk.sendPayment(request: request);
}

class BreezPaymentClient {
  final BreezPaymentGateway gateway;
  final String Function() createIdempotencyKey;

  const BreezPaymentClient({
    required this.gateway,
    required this.createIdempotencyKey,
  });

  Future<BreezPreparedPayment> prepare(
    String destination, {
    int? amountSats,
    InputType? parsedInput,
    FeePolicy? feePolicy,
  }) async {
    final trimmed = destination.trim();
    final parsed = parsedInput ?? await gateway.parse(trimmed);
    final payRequest = BreezPreparedPayment.lnurlPayRequestFor(parsed);

    if (payRequest != null) {
      if (amountSats == null) {
        throw ArgumentError(
          'amountSats é obrigatório para um endereço/link Lightning.',
        );
      }
      final response = await gateway.prepareLnurlPay(
        PrepareLnurlPayRequest(
          amount: BigInt.from(amountSats),
          payRequest: payRequest,
        ),
      );
      return BreezPreparedPayment.lnurl(response);
    }

    final response = await gateway.prepareSendPayment(
      PrepareSendPaymentRequest(
        paymentRequest: PaymentRequest.input(input: trimmed),
        amount: amountSats != null ? BigInt.from(amountSats) : null,
        feePolicy: feePolicy,
      ),
    );
    return BreezPreparedPayment.direct(
      response,
      createIdempotencyKey(),
    );
  }

  Future<Payment> send(
    BreezPreparedPayment prepared, {
    OnchainConfirmationSpeed onchainSpeed = OnchainConfirmationSpeed.medium,
  }) async {
    return switch (prepared) {
      BreezPreparedLnurl(:final response) => (await gateway.lnurlPay(
          LnurlPayRequest(prepareResponse: response),
        ))
            .payment,
      BreezPreparedDirect(:final response, :final idempotencyKey) =>
        (await gateway.sendPayment(
          SendPaymentRequest(
            prepareResponse: response,
            options: response.paymentMethod is SendPaymentMethod_BitcoinAddress
                ? SendPaymentOptions.bitcoinAddress(
                    confirmationSpeed: onchainSpeed,
                  )
                : null,
            idempotencyKey: idempotencyKey,
          ),
        ))
            .payment,
    };
  }
}

sealed class BreezPreparedPayment {
  const BreezPreparedPayment();

  const factory BreezPreparedPayment.direct(
    PrepareSendPaymentResponse response,
    String idempotencyKey,
  ) = BreezPreparedDirect;
  const factory BreezPreparedPayment.lnurl(PrepareLnurlPayResponse response) =
      BreezPreparedLnurl;

  static LnurlPayRequestDetails? lnurlPayRequestFor(InputType parsed) =>
      switch (parsed) {
        InputType_LightningAddress(:final field0) => field0.payRequest,
        InputType_LnurlPay(:final field0) => field0,
        _ => null,
      };

  bool get isOnchain => switch (this) {
        BreezPreparedDirect(:final response) =>
          response.paymentMethod is SendPaymentMethod_BitcoinAddress,
        BreezPreparedLnurl() => false,
      };

  BigInt feeFor(OnchainConfirmationSpeed speed) => switch (this) {
        BreezPreparedLnurl(:final response) => response.feeSats,
        BreezPreparedDirect(:final response) =>
          _feeForMethod(response.paymentMethod, speed),
      };

  static BigInt _feeForMethod(
    SendPaymentMethod method,
    OnchainConfirmationSpeed speed,
  ) =>
      switch (method) {
        SendPaymentMethod_BitcoinAddress(:final feeQuote) => switch (speed) {
            OnchainConfirmationSpeed.fast => feeQuote.speedFast.userFeeSat,
            OnchainConfirmationSpeed.medium => feeQuote.speedMedium.userFeeSat,
            OnchainConfirmationSpeed.slow => feeQuote.speedSlow.userFeeSat,
          },
        SendPaymentMethod_Bolt11Invoice(
          :final lightningFeeSats,
          :final sparkTransferFeeSats,
        ) =>
          lightningFeeSats + (sparkTransferFeeSats ?? BigInt.zero),
        SendPaymentMethod_SparkAddress(:final fee) => fee,
        SendPaymentMethod_SparkInvoice(:final fee) => fee,
        SendPaymentMethod_CrossChainAddress(:final feeAmount) => feeAmount,
      };
}

class BreezPreparedDirect extends BreezPreparedPayment {
  final PrepareSendPaymentResponse response;
  final String idempotencyKey;
  const BreezPreparedDirect(this.response, this.idempotencyKey);
}

class BreezPreparedLnurl extends BreezPreparedPayment {
  final PrepareLnurlPayResponse response;
  const BreezPreparedLnurl(this.response);
}
