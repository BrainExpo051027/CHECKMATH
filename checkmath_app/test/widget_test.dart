import 'package:flutter_test/flutter_test.dart';

import 'package:checkmath/main.dart';

void main() {
  testWidgets('CheckMath home loads', (WidgetTester tester) async {
    await tester.pumpWidget(const CheckMathApp());
    await tester.pumpAndSettle();
    expect(find.text('CheckMath'), findsWidgets);
    expect(find.text('Start game'), findsOneWidget);
  });
}
