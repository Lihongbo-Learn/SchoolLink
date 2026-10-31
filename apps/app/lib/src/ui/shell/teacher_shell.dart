import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../chat/chat_panel.dart';
import '../chat/stream_list.dart';
import '../motion.dart';
import '../settings/settings_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TeacherShell extends StatelessWidget {
  const TeacherShell({super.key, required this.controller});

  final AppController controller;

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(controller: controller),
      ),
    );
  }

  Future<void> _editClasses(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TeacherClassesDialog(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = controller.currentStream;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('教师端'),
            Text(
              controller.teacher?.name ?? '老师',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF7B8C84),
              ),
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: controller.connected ? '实时通道已连接' : '实时通道断开',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: OnlineDot(online: controller.connected, size: 9),
            ),
          ),
          IconButton(
            onPressed: () => _editClasses(context),
            icon: const Icon(Icons.tune_rounded),
            tooltip: '修改任教班级',
          ),
          IconButton(
            onPressed: () => _openSettings(context),
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          if (wide) {
            return Row(
              children: [
                SizedBox(
                  width: 350,
                  child: StreamListPanel(
                    controller: controller,
                    isClassroomView: false,
                    onSelected: (_) {},
                    onEditClasses: () => _editClasses(context),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Container(
                    color: AppColors.surface,
                    child: AnimatedSwitcher(
                      duration: AppMotion.standard,
                      switchInCurve: AppMotion.enter,
                      switchOutCurve: AppMotion.exit,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.015, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: stream == null
                          ? EmptyState(
                              key: const ValueKey('empty-teacher'),
                              icon: Icons.co_present_rounded,
                              title: '欢迎回来，${controller.teacher?.name ?? '老师'}',
                              message: '选择一个班级开始发送消息，或先设置任教班级。',
                              action: OutlinedButton(
                                onPressed: () => _editClasses(context),
                                child: const Text('修改任教班级'),
                              ),
                            )
                          : ChatPanel(
                              key: ValueKey(stream.id),
                              controller: controller,
                              stream: stream,
                              isClassroomView: false,
                            ),
                    ),
                  ),
                ),
              ],
            );
          }
          return StreamListPanel(
            controller: controller,
            isClassroomView: false,
            enableHero: true,
            onSelected: (stream) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: SafeArea(
                      bottom: false,
                      child: ChatPanel(
                        controller: controller,
                        stream: stream,
                        isClassroomView: false,
                        enableHero: true,
                        onBack: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ),
              );
            },
            onEditClasses: () => _editClasses(context),
          );
        },
      ),
    );
  }
}

class _TeacherClassesDialog extends StatefulWidget {
  const _TeacherClassesDialog({required this.controller});

  final AppController controller;

  @override
  State<_TeacherClassesDialog> createState() => _TeacherClassesDialogState();
}

class _TeacherClassesDialogState extends State<_TeacherClassesDialog> {
  late Set<String> _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(
      widget.controller.teacher?.classIds ?? const [],
    );
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      setState(() => _error = '请至少保留一个任教班级');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.updateTeacherClasses(_selected.toList());
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '任教班级',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '教室端会自动显示选择这些班级的老师。',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF70827A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClassPicker(
                selected: _selected,
                onChanged: (value) => setState(() => _selected = value),
                enabled: !_saving,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
