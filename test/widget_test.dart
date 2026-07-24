import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calculadora/main.dart';
import 'package:calculadora/routes.dart';
import 'package:calculadora/screens/calculator_screen.dart';
import 'package:calculadora/screens/pin_setup_screen.dart';

void main() {
  // The calculator's GridView only renders the buttons that fit in the
  // viewport, so tests that tap buttons in later rows (like '+' and '=')
  // fail on the default 800x600 surface. A tall surface ensures every row
  // is laid out.
  const surfaceSize = Size(420, 1400);

  testWidgets(
      'starts with zero and updates the display when digits are pressed',
      (tester) async {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(
        tester.widget<Text>(find.byKey(const ValueKey('display'))).data, '0');

    await tester.tap(find.text('7'));
    await tester.tap(find.text('8'));
    await tester.pump();

    expect(
        tester.widget<Text>(find.byKey(const ValueKey('display'))).data, '78');
  });

  testWidgets('21 followed by equals opens first-time setup', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.text('2'));
    await tester.tap(find.text('1'));
    await tester.tap(find.text('='));
    await tester.pumpAndSettle();

    expect(find.byType(PinSetupScreen), findsOneWidget);
  });

  testWidgets('adds two numbers and clears the display', (tester) async {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.text('7'));
    await tester.tap(find.text('+'));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('='));
    await tester.pumpAndSettle();

    expect(
        tester.widget<Text>(find.byKey(const ValueKey('display'))).data, '10');

    await tester.tap(find.text('AC'));
    await tester.pump();

    expect(
        tester.widget<Text>(find.byKey(const ValueKey('display'))).data, '0');
  });

  testWidgets('first digit replaces the initial zero', (tester) async {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.text('0').last);
    await tester.tap(find.text('5'));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('display'))).data,
      '5',
    );
  });

  testWidgets('repeated equals repeats the last operation', (tester) async {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.text('5'));
    await tester.tap(find.text('+'));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('='));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('display'))).data,
      '8',
    );

    await tester.tap(find.text('='));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('display'))).data,
      '11',
    );
  });

  testWidgets('division by zero shows an error and accepts a new number',
      (tester) async {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.text('8'));
    await tester.tap(find.text('÷'));
    await tester.tap(find.text('0').last);
    await tester.tap(find.text('='));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('display'))).data,
      'Erro',
    );

    await tester.tap(find.text('4'));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('display'))).data,
      '4',
    );
  });

  testWidgets('does not lock immediately after a brief app switch',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'satra_lock_timeout_minutes': '3',
    });
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final context = tester.element(find.byType(CalculatorScreen));
    Navigator.of(context).pushNamed(SatraRoutes.inheritancePassword);
    await tester.pumpAndSettle();
    expect(find.text('SENHA DE LIBERAÇÃO'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(CalculatorScreen), findsNothing);
    expect(find.text('SENHA DE LIBERAÇÃO'), findsOneWidget);
  });

  testWidgets('locks immediately when that timeout is selected',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'satra_lock_timeout_minutes': '0',
    });
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final context = tester.element(find.byType(CalculatorScreen));
    Navigator.of(context).pushNamed(SatraRoutes.inheritancePassword);
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(CalculatorScreen), findsOneWidget);
    expect(find.text('SENHA DE LIBERAÇÃO'), findsNothing);
  });
}
