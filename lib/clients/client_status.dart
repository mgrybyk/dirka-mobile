import 'package:material_ui/material_ui.dart';

import '../tunnel/tunnel_engine.dart';

class ClientStatus extends StatelessWidget {
  const ClientStatus({required this.status, this.stopping = false, super.key});

  final TunnelStatus status;
  final bool stopping;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final green = dark ? const Color(0xff92dca1) : const Color(0xff18642d);
    final amber = dark ? const Color(0xffffc56d) : const Color(0xff854900);
    final neutral = theme.colorScheme.onSurfaceVariant;
    final color = stopping
        ? neutral
        : switch (status) {
            TunnelStatus.connected || TunnelStatus.waitingForAgent => green,
            TunnelStatus.connecting => amber,
            TunnelStatus.stopped => neutral,
          };

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 8),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: !stopping && status == TunnelStatus.waitingForAgent
                ? Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Connected to relay',
                          style: TextStyle(color: green),
                        ),
                        TextSpan(
                          text: ' · ',
                          style: TextStyle(color: neutral),
                        ),
                        TextSpan(
                          text: 'Waiting for agent',
                          style: TextStyle(color: amber),
                        ),
                      ],
                    ),
                  )
                : Text(
                    stopping ? 'Disconnecting…' : status.label,
                    style: TextStyle(color: color),
                  ),
          ),
        ],
      ),
    );
  }
}
