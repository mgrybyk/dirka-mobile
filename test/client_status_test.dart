import 'package:dirka_mobile/clients/client_status.dart';
import 'package:dirka_mobile/tunnel/tunnel_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'shows accessible connection colors in ${brightness.name} mode',
      (tester) async {
        final theme = ThemeData(
          brightness: brightness,
          colorSchemeSeed: Colors.teal,
        );
        Future<void> show(TunnelStatus status) => tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SizedBox(
                width: 120,
                child: Card(child: ClientStatus(status: status)),
              ),
            ),
          ),
        );

        await show(TunnelStatus.connecting);
        final amber = tester
            .widget<Text>(find.text('Connecting'))
            .style!
            .color!;
        await show(TunnelStatus.connected);
        final green = tester
            .widget<Text>(find.text('Connected to agent'))
            .style!
            .color!;
        await show(TunnelStatus.stopped);
        final gray = tester
            .widget<Text>(find.text('Disconnected'))
            .style!
            .color!;
        expect({amber, green, gray}, hasLength(3));
        for (final color in [amber, green, gray]) {
          expect(
            _contrast(color, theme.colorScheme.surfaceContainerLow),
            greaterThanOrEqualTo(4.5),
          );
        }

        await show(TunnelStatus.waitingForAgent);
        final text = tester.widget<Text>(
          find.text(TunnelStatus.waitingForAgent.label),
        );
        final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
        expect(spans.map((span) => span.style!.color), [green, gray, amber]);
        final dot = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byType(ClientStatus),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect((dot.decoration as BoxDecoration).color, green);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + 0.05) / (second + 0.05)
      : (second + 0.05) / (first + 0.05);
}
