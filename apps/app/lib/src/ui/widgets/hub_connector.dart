import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/discovered_hub.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import 'common.dart';

class HubConnector extends StatefulWidget {
  const HubConnector({
    super.key,
    required this.controller,
    this.showDiscovery = true,
  });

  final AppController controller;
  final bool showDiscovery;

  @override
  State<HubConnector> createState() => _HubConnectorState();
}

class _HubConnectorState extends State<HubConnector> {
  late final TextEditingController _urlController;
  bool _busy = false;
  bool _discovering = false;
  String? _error;
  List<DiscoveredHub> _hubs = const [];

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.controller.hubUrl);
    if (widget.controller.hubUrl.isEmpty && kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.startsWith('http')) {
        _urlController.text = origin;
        widget.controller.setHubUrl(origin);
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.probeHub(_urlController.text);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discover() async {
    setState(() {
      _discovering = true;
      _error = null;
      _hubs = const [];
    });
    try {
      final hubs = await widget.controller.discoverHubs();
      if (!mounted) return;
      setState(() => _hubs = hubs);
      if (hubs.isEmpty) {
        setState(() => _error = '没有发现服务器，请检查是否在同一局域网或手动填写地址');
      }
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = widget.controller.hubInfo;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.dns_rounded, color: AppColors.primary, size: 22),
              SizedBox(width: 10),
              Text(
                '连接学校服务器',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Hub 由学校一台常开电脑运行；网页版也需要通过它访问。',
            style: TextStyle(fontSize: 13, color: Color(0xFF70827A)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            onChanged: widget.controller.setHubUrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: kIsWeb ? 'Hub 地址（当前网页服务器）' : 'Hub 地址',
              hintText: '例如 http://192.168.1.10:8421',
              prefixIcon: const Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _probe,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering_rounded, size: 19),
                label: const Text('检测连接'),
              ),
              if (widget.showDiscovery && !kIsWeb)
                OutlinedButton.icon(
                  onPressed: _discovering ? null : _discover,
                  icon: _discovering
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar_rounded, size: 19),
                  label: const Text('发现局域网服务器'),
                ),
            ],
          ),
          if (hub != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已连接：${hub.name}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hub ${hub.id.substring(0, hub.id.length.clamp(0, 8))} · v${hub.version}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF5C7168)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ],
          if (_hubs.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              '发现的服务器',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final hub in _hubs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dns_rounded, color: AppColors.primary),
                title: Text(hub.name),
                subtitle: Text(hub.url),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  _urlController.text = hub.url;
                  widget.controller.setHubUrl(hub.url);
                  _probe();
                },
              ),
          ],
        ],
      ),
    );
  }
}
