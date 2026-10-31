import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:school_link_protocol/protocol.dart';

import '../../services/hub_api.dart';
import '../../services/hub_runtime.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HubConsolePage extends StatefulWidget {
  const HubConsolePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HubConsolePage> createState() => _HubConsolePageState();
}

class _HubConsolePageState extends State<HubConsolePage> {
  final _pinController = TextEditingController(text: '246810');
  final _codeController = TextEditingController();
  final _maxFileController = TextEditingController();
  final _retentionController = TextEditingController();
  final _newAdminPinController = TextEditingController();
  AdminSnapshot? _snapshot;
  bool _loading = false;
  bool _starting = false;
  bool _requireCode = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    hubRuntime.addListener(_onRuntimeChanged);
    if (hubRuntime.running) {
      _refresh();
    }
  }

  @override
  void dispose() {
    hubRuntime.removeListener(_onRuntimeChanged);
    _pinController.dispose();
    _codeController.dispose();
    _maxFileController.dispose();
    _retentionController.dispose();
    _newAdminPinController.dispose();
    super.dispose();
  }

  void _onRuntimeChanged() {
    if (mounted) setState(() {});
  }

  HubApi _adminApi() => HubApi(baseUrl: hubRuntime.localUrl);

  Future<void> _startHub() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    await hubRuntime.start();
    if (!mounted) return;
    setState(() => _starting = false);
    if (hubRuntime.running) {
      await _refresh();
    } else {
      setState(() => _error = hubRuntime.error);
    }
  }

  Future<void> _stopHub() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('停止 Hub 服务？'),
        content: const Text('所有教室端和教师端会断开实时连接，网页端将不可用。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('停止'),
          ),
        ],
      ),
    );
    if (ok == true) await hubRuntime.stop();
    if (mounted) setState(() => _snapshot = null);
  }

  Future<void> _refresh() async {
    if (!hubRuntime.running) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = _adminApi();
    try {
      final snapshot = await api.adminSnapshot(_pinController.text.trim());
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _requireCode = snapshot.hub.registrationCodeRequired;
        _codeController.text = snapshot.registrationCode;
        _maxFileController.text = '${(snapshot.maxFileBytes / 1024 / 1024).round()}';
        _retentionController.text = '${snapshot.retentionDays}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      api.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runAdmin(Future<void> Function(HubApi api) action) async {
    final api = _adminApi();
    try {
      await action(api);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      api.close();
    }
  }

  Future<void> _resetPin(TeacherInfo teacher) async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('重置 ${teacher.name} 的 PIN'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: '新的 4–6 位 PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pin == null || pin.isEmpty) return;
    await _runAdmin((api) => api.adminResetPin(
          _pinController.text.trim(),
          teacher.id,
          pin,
        ));
  }

  Future<void> _saveRegistration(String pin) async {
    await _runAdmin((api) => api.adminSetRegistrationCode(
          pin,
          _codeController.text.trim(),
          required: _requireCode,
        ));
  }

  Future<void> _saveSettings(String pin) async {
    final maxMb = int.tryParse(_maxFileController.text.trim());
    final retention = int.tryParse(_retentionController.text.trim());
    await _runAdmin((api) => api.adminUpdateSettings(
          pin,
          maxFileBytes: maxMb == null ? null : maxMb * 1024 * 1024,
          retentionDays: retention,
        ));
  }

  Future<void> _changeAdminPin() async {
    final pin = _newAdminPinController.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理员 PIN 必须为 4–6 位数字')),
      );
      return;
    }
    await _runAdmin((api) => api.adminChangePin(_pinController.text.trim(), pin));
    _pinController.text = pin;
    _newAdminPinController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理员 PIN 已更新')),
      );
    }
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final running = hubRuntime.running;
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hub 管理台'),
        actions: [
          if (running)
            IconButton(
              onPressed: _loading ? null : _refresh,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: '刷新',
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      running ? Icons.dns_rounded : Icons.dns_outlined,
                      color: running ? AppColors.success : AppColors.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '本机中继服务',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            running
                                ? 'Hub 正在运行 · 数据与 Web 由本机提供'
                                : '在教室/教师电脑上运行 Hub，供全校客户端连接',
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF70827A)),
                          ),
                        ],
                      ),
                    ),
                    if (running)
                      OutlinedButton(
                        onPressed: _stopHub,
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                        child: const Text('停止服务'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _starting ? null : _startHub,
                        icon: _starting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                        label: const Text('启动 Hub'),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                ],
                if (running) ...[
                  const SizedBox(height: 16),
                  for (final url in hubRuntime.urls)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link_rounded, size: 20),
                      title: SelectableText(url),
                      trailing: IconButton(
                        onPressed: () => _copy(url),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (hubRuntime.urls.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: QrImageView(
                            data: hubRuntime.urls.first,
                            size: 140,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _InfoLine(label: '数据目录', value: hubRuntime.dataDir ?? '-'),
                          _InfoLine(
                            label: 'Web 目录',
                            value: hubRuntime.webRoot ?? '未找到构建产物',
                          ),
                          if (!hubRuntime.hasWebBuild)
                            const Text(
                              '提示：把 Flutter Web 构建产物复制到程序目录下的 web 文件夹后，浏览器即可访问。',
                              style: TextStyle(fontSize: 11.5, color: AppColors.amber),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (running) ...[
            const SizedBox(height: 16),
            SectionCard(
              child: Row(
                children: [
                  const Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '管理员 PIN（默认 246810）',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonal(
                    onPressed: _loading ? null : _refresh,
                    child: const Text('验证'),
                  ),
                ],
              ),
            ),
            if (snapshot != null) ...[
              const SizedBox(height: 16),
              _overview(snapshot),
              const SizedBox(height: 16),
              _teachers(snapshot),
              const SizedBox(height: 16),
              _classrooms(snapshot),
              const SizedBox(height: 16),
              _settings(snapshot),
            ],
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _overview(AdminSnapshot snapshot) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('概览', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Stat(label: '教师', value: '${snapshot.teachers.length}'),
              _Stat(label: '教室设备', value: '${snapshot.classrooms.length}'),
              _Stat(label: '在线设备', value: '${snapshot.onlineDevices.length}'),
              _Stat(label: '文件数量', value: '${snapshot.fileCount}'),
              _Stat(label: '文件占用', value: formatFileSize(snapshot.fileBytes)),
            ],
          ),
          if (snapshot.onlineDevices.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              '当前在线',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final device in snapshot.onlineDevices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    OnlineDot(online: true, size: 7),
                    const SizedBox(width: 8),
                    Text(
                      device.role == senderTeacher
                          ? '教师 · ${device.machineName}'
                          : '教室 · ${classTitle(device.classId)} · ${device.machineName}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _teachers(AdminSnapshot snapshot) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '教师账号（${snapshot.teachers.length}）',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (snapshot.teachers.isEmpty)
            const Text('暂无教师账号', style: TextStyle(color: Color(0xFF82938B)))
          else
            for (final teacher in snapshot.teachers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(name: teacher.name, size: 38),
                title: Row(
                  children: [
                    Text(teacher.name),
                    if (teacher.disabled) ...[
                      const SizedBox(width: 8),
                      const Text(
                        '已停用',
                        style: TextStyle(fontSize: 11, color: AppColors.danger),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  teacher.classIds
                      .map((id) => parseClassId(id)?.title ?? id)
                      .join('、'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'pin') _resetPin(teacher);
                    if (value == 'toggle') {
                      _runAdmin((api) => api.adminSetTeacherDisabled(
                            _pinController.text.trim(),
                            teacher.id,
                            !teacher.disabled,
                          ));
                    }
                    if (value == 'remove') {
                      _runAdmin((api) => api.adminRemoveTeacher(
                            _pinController.text.trim(),
                            teacher.id,
                          ));
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'pin', child: Text('重置 PIN')),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(teacher.disabled ? '启用账号' : '停用账号'),
                    ),
                    const PopupMenuItem(value: 'remove', child: Text('删除账号')),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _classrooms(AdminSnapshot snapshot) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '教室设备（${snapshot.classrooms.length}）',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (snapshot.classrooms.isEmpty)
            const Text('暂无教室设备', style: TextStyle(color: Color(0xFF82938B)))
          else
            for (final classroom in snapshot.classrooms)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tv_rounded, color: AppColors.primary),
                title: Text(classTitle(classroom.classId)),
                subtitle: Text(
                  '${classroom.machineName} · ${formatFullTime(classroom.lastSeenAt)}',
                ),
                trailing: TextButton(
                  onPressed: () => _runAdmin((api) => api.adminRemoveClassroom(
                        _pinController.text.trim(),
                        classroom.id,
                      )),
                  child: const Text('移除'),
                ),
              ),
        ],
      ),
    );
  }

  Widget _settings(AdminSnapshot snapshot) {
    final pin = _pinController.text.trim();
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('设置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '教师注册码',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: _requireCode,
                onChanged: (value) => setState(() => _requireCode = value),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(labelText: '注册码（留空则不限制）'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: () => _saveRegistration(pin),
                child: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maxFileController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '单文件上限（MB）'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _retentionController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '文件保留天数'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: () => _saveSettings(pin),
                child: const Text('保存'),
              ),
            ],
          ),
          const Divider(height: 32),
          const Text(
            '修改管理员 PIN',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newAdminPinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '新的 4–6 位 PIN',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: _changeAdminPin,
                child: const Text('更新'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Hub 版本 ${snapshot.hub.version} · 启动于 ${formatFullTime(snapshot.startedAt)}',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A9A92)),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF7B8C84)),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        '$label：$value',
        style: const TextStyle(fontSize: 11.5, color: Color(0xFF7B8C84)),
      ),
    );
  }
}
