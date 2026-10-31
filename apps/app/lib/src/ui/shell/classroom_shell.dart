import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../chat/chat_panel.dart';
import '../chat/stream_list.dart';
import '../motion.dart';
import '../settings/settings_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ClassroomShell extends StatelessWidget {
  const ClassroomShell({super.key, required this.controller});

  final AppController controller;

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(controller: controller),
      ),
    );
  }

  void _openNoticeHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoticeHistoryPage(controller: controller),
      ),
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
            Text('${controller.currentClassTitle} · 教室端'),
            Row(
              children: [
                OnlineDot(online: controller.connected, size: 7),
                const SizedBox(width: 5),
                Text(
                  controller.connected ? '实时在线' : '离线 · 数据为本地缓存',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF7B8C84),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _openNoticeHistory(context),
            icon: const Icon(Icons.history_rounded),
            tooltip: '全部通知历史',
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
                  width: 340,
                  child: StreamListPanel(
                    controller: controller,
                    isClassroomView: true,
                    onSelected: (_) {},
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
                          ? const EmptyState(
                              key: ValueKey('empty-classroom'),
                              icon: Icons.tv_rounded,
                              title: '等待老师加入',
                              message: '老师在教师端选择本班后，会话会出现在这里。',
                            )
                          : ChatPanel(
                              key: ValueKey(stream.id),
                              controller: controller,
                              stream: stream,
                              isClassroomView: true,
                            ),
                    ),
                  ),
                ),
              ],
            );
          }
          return StreamListPanel(
            controller: controller,
            isClassroomView: true,
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
                        isClassroomView: true,
                        enableHero: true,
                        onBack: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
