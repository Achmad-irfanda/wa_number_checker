// Integration test: runs on-device (needs contacts permission granted
// manually on first run). Kept offline-friendly: only asserts device info
// resolves without throwing.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:wa_number_checker/wa_number_checker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getDeviceInfo resolves', (WidgetTester tester) async {
    final checker = WaNumberChecker();
    final info = await checker.getDeviceInfo();
    expect(info, isA<WaDeviceInfo>());
    checker.dispose();
  });
}
