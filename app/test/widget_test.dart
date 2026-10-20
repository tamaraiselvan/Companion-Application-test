import 'package:flutter_test/flutter_test.dart';
import 'package:dayfello/screens/auth.dart';
import 'package:dayfello/widgets.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('Onboarding walks through to the policy step', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const OnboardingScreen()));
    expect(find.text('Trusted human companionship'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pump();
    }
    expect(find.text('Get started'), findsOneWidget);
  });

  test('helpers', () {
    expect(initials('Priya Raman'), 'PR');
    expect(inr(600), '₹600');
  });
}
