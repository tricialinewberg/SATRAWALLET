import 'package:calculadora/screens/inheritance_claim_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Argon2id is memory-hard (19 MiB, 3 iterations) and blocks the platform
  // thread for several seconds in the test environment. We avoid running
  // a real decrypt inside widget tests — the crypto round-trip is already
  // covered exhaustively in nfc_credential_crypto_test.dart. Here we only
  // verify the UI: empty-input validation and the presence of the form
  // fields the heir needs.
  testWidgets('shows error when decrypting with empty envelope', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(home: InheritanceClaimScreen()));
    await tester.pump();

    await tester.tap(find.text('Decifrar'));
    await tester.pumpAndSettle();

    expect(find.text('Cole o envelope cifrado recebido via Nostr.'),
        findsOneWidget);
  });

  testWidgets('shows error when envelope present but password empty',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(home: InheritanceClaimScreen()));
    await tester.pump();

    await tester.enterText(
      find.byType(TextField).first,
      '{"version":1,"walletType":"breez-spark"}',
    );
    await tester.tap(find.text('Decifrar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Digite a senha de liberação combinada com o titular.'),
      findsOneWidget,
    );
  });

  testWidgets('has the three expected input fields and a decrypt button',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(home: InheritanceClaimScreen()));
    await tester.pump();

    expect(find.text('Envelope cifrado'), findsOneWidget);
    expect(find.text('Senha de liberação'), findsOneWidget);
    expect(find.text('Decifrar'), findsOneWidget);
  });
}
