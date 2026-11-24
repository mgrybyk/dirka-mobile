import 'package:flutter/services.dart';

import '../tunnel/native_tunnel_engine.dart';
import 'app_info.dart';

final class AndroidAppInfo implements AppInfo {
  const AndroidAppInfo();

  static const _channel = MethodChannel('com.mgrybyk.dirka/app_info');

  @override
  Future<AppVersion> loadAppVersion() async {
    final package = await _channel.invokeMapMethod<String, String>(
      'appVersion',
    );
    return (
      version: package!['version']!,
      buildNumber: package['buildNumber']!,
    );
  }

  @override
  Future<EngineInfo> loadEngineInfo() => NativeTunnelEngine.loadInfo();

  @override
  Future<bool> openUpstreamRepository() async =>
      await _channel.invokeMethod<bool>('openUpstreamRepository') ?? false;
}
