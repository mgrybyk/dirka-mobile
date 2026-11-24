import 'package:material_ui/material_ui.dart';

import 'probe/probe_screen.dart';
import 'tunnel/native_tunnel_engine.dart';
import 'tunnel/tunnel_engine.dart';

void main() => runApp(const DirkaApp());

class DirkaApp extends StatelessWidget {
  const DirkaApp({this.engine = const NativeTunnelEngine(), super.key});

  final TunnelEngine engine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dirka',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: ProbeScreen(engine: engine),
    );
  }
}
