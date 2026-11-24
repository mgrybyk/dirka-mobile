typedef AppVersion = ({String version, String buildNumber});
typedef EngineInfo = ({
  String engineVersion,
  int protocolVersion,
  String upstreamRevision,
  String upstreamLicense,
});

abstract interface class AppInfo {
  Future<AppVersion> loadAppVersion();
  Future<EngineInfo> loadEngineInfo();
  Future<bool> openUpstreamRepository();
}
