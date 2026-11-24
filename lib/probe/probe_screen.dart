import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../tunnel/tunnel_engine.dart';
import 'probe_controller.dart';

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({required this.engine, super.key});

  final TunnelEngine engine;

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  final _form = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _relayPort = TextEditingController();
  final _route = TextEditingController();
  final _key = TextEditingController();
  final _localPort = TextEditingController(text: '18080');
  late final _controller = ProbeController(widget.engine);
  bool _tls = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dirka')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final active = _controller.active;
          final state = _controller.state;
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _textField('Relay host', _host, active, _required),
                      _portField('Relay port', _relayPort, active),
                      _textField('Route ID', _route, active, _required),
                      _textField(
                        'Shared key',
                        _key,
                        active,
                        _validateKey,
                        secret: true,
                      ),
                      _portField('Local port on 127.0.0.1', _localPort, active),
                      SwitchListTile(
                        title: const Text('Use TLS'),
                        value: _tls,
                        onChanged: active
                            ? null
                            : (value) => setState(() => _tls = value),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _controller.stopping
                              ? 'Disconnecting…'
                              : state.status.label,
                        ),
                      ),
                      if (state.error case final error?)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              error,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _controller.starting || _controller.stopping
                            ? null
                            : active
                            ? _controller.stop
                            : _connect,
                        child: Text(active ? 'Disconnect' : 'Connect'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _portField(
    String label,
    TextEditingController controller,
    bool active,
  ) {
    return _textField(label, controller, active, (value) {
      final port = int.tryParse(value?.trim() ?? '');
      return port == null || port < 1 || port > 65535
          ? 'Enter a port from 1 to 65535.'
          : null;
    }, keyboard: TextInputType.number);
  }

  Widget _textField(
    String label,
    TextEditingController controller,
    bool active,
    String? Function(String?) validator, {
    TextInputType? keyboard,
    bool secret = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: !active,
        keyboardType: keyboard,
        autocorrect: !secret,
        enableSuggestions: !secret,
        obscureText: secret,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: validator,
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required.' : null;

  String? _validateKey(String? value) => utf8.encode(value ?? '').length == 32
      ? null
      : 'The key must contain 32 UTF-8 bytes.';

  void _connect() {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _controller.start(
      TunnelConfig(
        relayHost: _host.text.trim(),
        relayPort: int.parse(_relayPort.text.trim()),
        route: _route.text,
        key: _key.text,
        bindHost: '127.0.0.1',
        ports: [int.parse(_localPort.text.trim())],
        tls: _tls,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _host.dispose();
    _relayPort.dispose();
    _route.dispose();
    _key.dispose();
    _localPort.dispose();
    super.dispose();
  }
}
