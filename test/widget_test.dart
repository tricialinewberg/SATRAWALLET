import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calculadora/main.dart';

void main() {
  testWidgets('starts with zero and updates the display when digits are pressed', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(tester.widget<Text>(find.byKey(const ValueKey('display'))).data, '0');

    await tester.tap(find.text('7'));
    await tester.tap(find.text('8'));
    await tester.pump();

    expect(tester.widget<Text>(find.byKey(const ValueKey('display'))).data, '78');
  });

  testWidgets('adds two numbers and clears the display', (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('7'));
    await tester.tap(find.byKey(const ValueKey('plus_button')));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('='));
    await tester.pump();

    expect(tester.widget<Text>(find.byKey(const ValueKey('display'))).data, '10');

    await tester.tap(find.text('AC'));
    await tester.pump();

    expect(tester.widget<Text>(find.byKey(const ValueKey('display'))).data, '0');
  });
}
