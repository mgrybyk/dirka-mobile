import 'package:material_ui/material_ui.dart';

import 'app_info.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({required this.info, super.key});

  final AppInfo info;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final _version = widget.info.loadAppVersion();
  late final _engine = widget.info.loadEngineInfo();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              FutureBuilder<AppVersion>(
                future: _version,
                builder: (context, snapshot) => ListTile(
                  title: const Text('App version'),
                  subtitle: Text(switch (snapshot.data) {
                    final version? =>
                      '${version.version} (build ${version.buildNumber})',
                    _ => snapshot.hasError ? 'Unavailable' : 'Loading…',
                  }),
                ),
              ),
              FutureBuilder<EngineInfo>(
                future: _engine,
                builder: (context, snapshot) {
                  final engine = snapshot.data;
                  if (engine == null) {
                    return ListTile(
                      title: const Text('Tunnel engine'),
                      subtitle: Text(
                        snapshot.hasError ? 'Unavailable' : 'Loading…',
                      ),
                    );
                  }
                  return Column(
                    children: [
                      ListTile(
                        title: const Text('Protocol version'),
                        subtitle: Text('${engine.protocolVersion}'),
                      ),
                      ListTile(
                        title: const Text('Engine version'),
                        subtitle: Text(engine.engineVersion),
                      ),
                      ListTile(
                        title: const Text('node-tunnel commit'),
                        subtitle: SelectableText(engine.upstreamRevision),
                      ),
                    ],
                  );
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('node-tunnel on GitHub'),
                trailing: const Icon(Icons.open_in_new),
                onTap: _openRepository,
              ),
              ListTile(
                title: const Text('Open-source licenses'),
                onTap: () =>
                    showLicensePage(context: context, applicationName: 'Dirka'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _openRepository() async {
    try {
      if (await widget.info.openUpstreamRepository()) return;
    } on Object {
      // The app can still display the build details if the browser is unavailable.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the node-tunnel repository.'),
        ),
      );
    }
  }
}
