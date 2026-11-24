import 'package:material_ui/material_ui.dart';

import 'clients/client_repository.dart';
import 'clients/clients_screen.dart';
import 'tunnel/native_tunnel_engine.dart';
import 'tunnel/tunnel_engine.dart';

void main() => runApp(const DirkaApp());

class DirkaApp extends StatelessWidget {
  const DirkaApp({
    this.engine = const NativeTunnelEngine(),
    this.repository = const SecureClientRepository(),
    super.key,
  });

  final TunnelEngine engine;
  final ClientRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dirka',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: ClientsScreen(engine: engine, repository: repository),
    );
  }
}
