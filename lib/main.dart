import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'app_info/android_app_info.dart';
import 'app_info/app_info.dart';
import 'clients/client_repository.dart';
import 'clients/clients_screen.dart';
import 'tunnel/android_tunnel_runtime.dart';
import 'tunnel/native_engine_info.dart';
import 'tunnel/tunnel_engine.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    try {
      final info = await NativeEngineInfo.loadInfo();
      yield LicenseEntryWithLineBreaks(['node-tunnel'], info.upstreamLicense);
      for (final license in await NativeEngineInfo.loadDependencyLicenses()) {
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
    this.runtime = const AndroidTunnelRuntime(),
    this.repository = const SecureClientRepository(),
    this.appInfo = const AndroidAppInfo(),
    super.key,
  });

  final TunnelRuntime runtime;
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
        runtime: runtime,
        repository: repository,
        appInfo: appInfo,
      ),
    );
  }
}
