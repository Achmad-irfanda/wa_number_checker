import 'package:flutter_test/flutter_test.dart';
import 'package:wa_number_checker_example/main.dart';

void main() {
  testWidgets('Example renders registration form', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('wa_number_checker example'), findsOneWidget);
    expect(find.text('2. Verify sekarang'), findsOneWidget);
  });
}
