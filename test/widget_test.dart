// test/widget_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xemu/main.dart';

/// path_provider has no native side in unit tests, so point it at a temp folder.
class _FakePathProvider extends PathProviderPlatform {
  final String dir;
  _FakePathProvider(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

void main() {
  late Directory tmp;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('tonemu_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('tonEMU launcher smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TonEmuApp());
    await tester.pumpAndSettle(); // let the async library load finish

    expect(find.text('tonEMU'), findsOneWidget);
    expect(find.text('No Games Yet'), findsOneWidget);
    expect(find.text('In memory of Ton · 2026'), findsOneWidget);
  });
}
