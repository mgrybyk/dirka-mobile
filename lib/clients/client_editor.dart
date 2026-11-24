import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'client_config.dart';
import 'clients_controller.dart';

class ClientEditor extends StatefulWidget {
  const ClientEditor({
    required this.title,
    required this.onSave,
    this.initialSource = '',
    super.key,
  });

  final String title;
  final String initialSource;
  final Future<void> Function(String source) onSave;

  @override
  State<ClientEditor> createState() => _ClientEditorState();
}

class _ClientEditorState extends State<ClientEditor> {
  late final _text = TextEditingController(text: widget.initialSource);
  String? _error;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    var exposesNetwork = false;
    try {
      exposesNetwork = parseClientConfig(_text.text).exposesNetwork;
    } on FormatException {
      // Show validation feedback after the user tries to save.
    }
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _paste,
                      icon: const Icon(Icons.content_paste),
                      label: const Text('Paste'),
                    ),
                  ),
                  TextField(
                    controller: _text,
                    readOnly: _saving,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    minLines: 8,
                    maxLines: 16,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: 'Node-tunnel configuration',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  if (_error case final error?)
                    _feedback(error, Theme.of(context).colorScheme.error),
                  if (exposesNetwork)
                    _feedback(
                      'This bind host may make the forwarded ports reachable from other devices.',
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Saving…' : 'Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _feedback(String message, Color color) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(message, style: TextStyle(color: color)),
    ),
  );

  Future<void> _paste() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || _saving) return;
    final value = clipboard?.text;
    setState(() {
      if (value == null || value.isEmpty) {
        _error = 'The clipboard has no text.';
      } else {
        _text.text = value;
        _error = null;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_text.text);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on ClientEditError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }
}
