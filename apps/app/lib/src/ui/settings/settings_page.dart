import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:school_link_protocol/protocol.dart';

import '../../services/platform_service.dart';
import '../../state/app_controller.dart';
import '../hub/hub_console_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  Future<void> _reset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置本机配置'),
        content: const Text(
          '这会清除本机的模式、登录状态和聊天缓存，用于开发测试。正式使用的教室端不应执行此操作。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.resetEverything();
      if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teacherClassNames = (controller.teacher?.classIds ?? const <String>[])
        .map((id) => parseClassId(id)?.title ?? id)
        .join('、');
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.school_rounded, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text(
                      controller.isClassroom
                          ? '${controller.currentClassTitle} · 教室端'
                          : '教师端 · ${controller.teacher?.name ?? ''}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _InfoRow(label: '连接状态', value: controller.connected ? '实时在线' : '离线'),
                _InfoRow(
                  label: 'Hub',
                  value: controller.hubInfo == null
                      ? (controller.hubUrl.isEmpty ? '未配置' : controller.hubUrl)
                      : '${controller.hubInfo!.name}（${controller.hubUrl}）',
                ),
                _InfoRow(label: '设备标识', value: controller.installId ?? '-'),
                _InfoRow(label: '服务器时间', value: controller.serverOffsetLabel),
                if (controller.isClassroom)
                  const _InfoRow(label: '模式', value: '教室模式已锁定，需卸载重装才能更改'),
                if (!controller.isClassroom && teacherClassNames.isNotEmpty)
                  _InfoRow(label: '任教班级', value: teacherClassNames),
                if (controller.isWeb)
                  const _InfoRow(label: 'Web 限制', value: '全屏需点击授权；自动下载受浏览器限制'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: controller.retryConnection,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('重新连接'),
                    ),
                    if (platform.canHostHub)
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => HubConsolePage(controller: controller),
                          ),
                        ),
                        icon: const Icon(Icons.dns_rounded, size: 18),
                        label: const Text('Hub 管理台'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                SwitchListTile(
                  value: controller.soundEnabled,
                  onChanged: controller.setSoundEnabled,
                  title: const Text('提示音'),
                  subtitle: const Text('接收全屏通知时播放提示音（老师仍可为单条通知关闭）'),
                  secondary: const Icon(Icons.volume_up_outlined),
                ),
                if (platform.canAutoStart) ...[
                  const Divider(height: 1),
                  _AutoStartTile(),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('文件保存位置'),
                  subtitle: Text(
                    platform.isDesktop
                        ? '下载\\校联\\<班级>\\<日期>\\<老师>'
                        : (platform.name == 'Web'
                            ? '浏览器下载目录'
                            : '应用专属文件目录 / 系统下载目录'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '关于',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  '校联 SchoolLink · 校园局域网文件共享与全屏通知',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7C74)),
                ),
                const SizedBox(height: 4),
                Text(
                  '版本 $appVersion · ${platform.name}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A9A92)),
                ),
                if (kDebugMode) ...[
                  const Divider(height: 28),
                  TextButton.icon(
                    onPressed: () => _reset(context),
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('重置本机配置（仅调试版）'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF82938B)),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF3E5048)),
            ),
          ),
        ],
      ),
    );
  }
}


class _AutoStartTile extends StatefulWidget {
  const _AutoStartTile();

  @override
  State<_AutoStartTile> createState() => _AutoStartTileState();
}

class _AutoStartTileState extends State<_AutoStartTile> {
  bool? _value;

  @override
  void initState() {
    super.initState();
    platform.isAutoStartEnabled().then((value) {
      if (mounted) setState(() => _value = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: _value ?? false,
      onChanged: _value == null
          ? null
          : (value) async {
              setState(() => _value = value);
              await platform.setAutoStart(value);
            },
      title: const Text('开机自动启动'),
      subtitle: const Text('Windows 登录后自动打开校联（Hub 主机或教室大屏可用）'),
      secondary: const Icon(Icons.rocket_launch_outlined),
    );
  }
}
