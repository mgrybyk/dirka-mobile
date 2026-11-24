import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'app_info/android_app_info.dart';
import 'app_info/app_info.dart';
import 'clients/client_repository.dart';
import 'clients/clients_screen.dart';
import 'tunnel/native_tunnel_engine.dart';
import 'tunnel/tunnel_engine.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    try {
      final info = await NativeTunnelEngine.loadInfo();
      yield LicenseEntryWithLineBreaks(['node-tunnel'], info.upstreamLicense);
      for (final license in await NativeTunnelEngine.loadDependencyLicenses()) {
        yield LicenseEntryWithLineBreaks(license.packages, license.text);
      }
    } on Object {
      // The SDK and Dart licenses remain available if the native library fails to load.
    }
  });
  runApp(const DirkaApp());
}

class DirkaApp extends StatelessWidget {
  const DirkaApp({
    this.engine = const NativeTunnelEngine(),
    this.repository = const SecureClientRepository(),
    this.appInfo = const AndroidAppInfo(),
    super.key,
  });

  final TunnelEngine engine;
  final ClientRepository repository;
  final AppInfo appInfo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dirka',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: ClientsScreen(
        engine: engine,
        repository: repository,
        appInfo: appInfo,
      ),
    );
  }
}
