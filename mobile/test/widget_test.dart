import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bocadoo/main.dart';

void main() {
  testWidgets('Bocadoo app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: BocadooApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify that the login screen and Bocadoo branding are shown
    expect(find.text('bocadoo'), findsOneWidget);
    expect(find.text('Comensal'), findsOneWidget);
    expect(find.text('Dueño'), findsOneWidget);
  });
}
