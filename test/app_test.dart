import 'package:dirka_mobile/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows Dirka and follows system brightness', (tester) async {
    final dispatcher = tester.platformDispatcher;
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const DirkaApp());

    final title = find.text('Dirka');
    expect(title, findsOneWidget);
    expect(Theme.of(tester.element(title)).brightness, Brightness.dark);
  });
}
