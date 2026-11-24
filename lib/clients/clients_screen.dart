import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_info/about_screen.dart';
import '../app_info/app_info.dart';
import '../app_info/settings_screen.dart';
import '../tunnel/tunnel_engine.dart';
import 'client_editor.dart';
import 'client_repository.dart';
import 'client_status.dart';
import 'clients_controller.dart';

enum _AppAction { settings, about }

enum _Action { edit, duplicate, delete }

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({
    required this.runtime,
    required this.repository,
    required this.appInfo,
    super.key,
  });

  final TunnelRuntime runtime;
  final ClientRepository repository;
  final AppInfo appInfo;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  late final _controller = ClientsController(widget.repository, widget.runtime);

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final canAdd = _controller.ready && !_controller.saving;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Dirka'),
          actions: [
            PopupMenuButton<_AppAction>(
              tooltip: 'App menu',
              onSelected: _openAppPage,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _AppAction.settings,
                  child: Text('Settings'),
                ),
                PopupMenuItem(value: _AppAction.about, child: Text('About')),
              ],
            ),
          ],
        ),
        floatingActionButton: _controller.entries.isEmpty || !canAdd
            ? null
            : FloatingActionButton.extended(
                onPressed: _openEditor,
                icon: const Icon(Icons.add),
                label: const Text('Add client'),
              ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _buildBody(canAdd),
            ),
          ),
        ),
      );
    },
  );

  Widget _buildBody(bool canAdd) {
    if (_controller.loading) {
      return const CircularProgressIndicator(
        semanticsLabel: 'Loading saved clients',
      );
    }
    if (_controller.loadError case final error?) {
      return _centeredPanel(
        error,
        FilledButton(onPressed: _controller.load, child: const Text('Retry')),
      );
    }
    if (_controller.entries.isEmpty) {
      return _centeredPanel(
        'No saved clients',
        FilledButton.icon(
          onPressed: canAdd ? _openEditor : null,
          icon: const Icon(Icons.add),
          label: const Text('Add client'),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: _controller.entries.length,
      itemBuilder: (context, index) {
        final entry = _controller.entries[index];
        return _clientCard(context, entry);
      },
    );
  }

  Widget _centeredPanel(String message, Widget action) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (constraints.maxHeight - 32)
              .clamp(0, double.infinity)
              .toDouble(),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text(message), const SizedBox(height: 12), action],
        ),
      ),
    ),
  );

  Widget _clientCard(BuildContext context, ClientEntry entry) {
    final runtime = _controller.runtime(entry.id);
    final active = runtime?.active ?? false;
    final status = runtime?.status ?? TunnelStatus.stopped;
    final commandPending = _controller.commandPending(entry.id);
    final config = entry.config.tunnel;
    final theme = Theme.of(context);
    return Card(
      key: ValueKey(entry.id),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.route,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        config.relayHost,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_Action>(
                  enabled: !_controller.saving,
                  tooltip: 'Client actions',
                  onSelected: (action) => _handleAction(entry, action),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _Action.edit,
                      enabled: !active && !commandPending,
                      child: const Text('Edit'),
                    ),
                    const PopupMenuItem(
                      value: _Action.duplicate,
                      child: Text('Duplicate'),
                    ),
                    PopupMenuItem(
                      value: _Action.delete,
                      enabled: !active && !commandPending,
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClientStatus(status: status, stopping: runtime?.stopping ?? false),
            Text('Bind host: ${config.bindHost}'),
            Text('Ports: ${entry.config.portsText}'),
            if (_controller.commandError(entry.id) ?? runtime?.error
                case final error?)
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                onPressed: commandPending || (runtime?.stopping ?? false)
                    ? null
                    : active
                    ? () => _controller.disconnect(entry.id)
                    : _controller.saving
                    ? null
                    : () => _controller.connect(entry),
                child: Text(active ? 'Disconnect' : 'Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAppPage(_AppAction action) {
    final page = switch (action) {
      _AppAction.settings => const SettingsScreen(),
      _AppAction.about => AboutScreen(info: widget.appInfo),
    };
    Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (context) => page));
  }

  Future<void> _openEditor([ClientEntry? entry, bool duplicate = false]) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => ClientEditor(
            title: duplicate
                ? 'Duplicate client'
                : entry == null
                ? 'Add client'
                : 'Edit client',
            initialSource: entry?.source ?? '',
            onSave: (source) =>
                _controller.save(source, id: duplicate ? null : entry?.id),
          ),
        ),
      );

  Future<void> _handleAction(ClientEntry entry, _Action action) async {
    switch (action) {
      case _Action.edit:
        await _openEditor(entry);
      case _Action.duplicate:
        await _openEditor(entry, true);
      case _Action.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete client?'),
            content: Text(entry.config.tunnel.route),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        try {
          await _controller.delete(entry.id);
        } on ClientEditError catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error.message)));
          }
        }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
