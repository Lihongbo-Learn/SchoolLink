import 'package:flutter/material.dart';
import 'package:school_link_protocol/protocol.dart';

import '../../state/app_controller.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/common.dart';

class StreamListPanel extends StatelessWidget {
  const StreamListPanel({
    super.key,
    required this.controller,
    required this.isClassroomView,
    required this.onSelected,
    this.onEditClasses,
    this.enableHero = false,
  });

  final AppController controller;
  final bool isClassroomView;
  final ValueChanged<StreamInfo> onSelected;
  final VoidCallback? onEditClasses;
  final bool enableHero;

  @override
  Widget build(BuildContext context) {
    final streams = controller.streams;
    return Container(
      color: const Color(0xFFF7F9F8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isClassroomView ? '科任老师' : '任教班级',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isClassroomView
                            ? '共 ${streams.length} 位老师 · 点击查看通知'
                            : '共 ${streams.length} 个班级',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF82938B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isClassroomView && onEditClasses != null)
                  IconButton(
                    onPressed: onEditClasses,
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: '修改任教班级',
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: streams.isEmpty
                ? EmptyState(
                    icon: isClassroomView
                        ? Icons.groups_outlined
                        : Icons.class_outlined,
                    title: isClassroomView ? '还没有老师加入' : '还没有任教班级',
                    message: isClassroomView
                        ? '老师在教师端选择本班后，会显示在这里。'
                        : '先选择任教的班级，才能发送通知和文件。',
                    action: !isClassroomView && onEditClasses != null
                        ? OutlinedButton(
                            onPressed: onEditClasses,
                            child: const Text('选择任教班级'),
                          )
                        : null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    itemCount: streams.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final stream = streams[index];
                      final selected =
                          controller.currentStream?.id == stream.id;
                      final unread = controller.unreadFor(stream.id);
                      final online = isClassroomView
                          ? controller.onlineTeacher(stream.teacherId)
                          : controller.onlineClass(stream.classId);
                      final title = isClassroomView
                          ? (stream.teacherName.isEmpty
                                ? '老师'
                                : stream.teacherName)
                          : (stream.className.isEmpty
                                ? classTitle(stream.classId)
                                : stream.className);
                      final subtitle = stream.lastMessagePreview.isEmpty
                          ? (isClassroomView ? '暂无消息' : '点击发送第一条消息')
                          : stream.lastMessagePreview;
                      return AnimatedContainer(
                        duration: AppMotion.standard,
                        curve: AppMotion.enter,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              controller.setCurrentStream(stream.id);
                              onSelected(stream);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      if (enableHero)
                                        Hero(
                                          tag: 'stream-avatar-${stream.id}',
                                          child: Material(
                                            type: MaterialType.transparency,
                                            child: Avatar(
                                              name: title,
                                              size: 44,
                                              color: isClassroomView
                                                  ? null
                                                  : AppColors.primary,
                                            ),
                                          ),
                                        )
                                      else
                                        Avatar(
                                          name: title,
                                          size: 44,
                                          color: isClassroomView
                                              ? null
                                              : AppColors.primary,
                                        ),
                                      Positioned(
                                        right: -1,
                                        bottom: -1,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFF7F9F8),
                                            shape: BoxShape.circle,
                                          ),
                                          child: OnlineDot(
                                            online: online,
                                            size: 9,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            if (stream.lastMessageAt > 0)
                                              Text(
                                                formatClock(
                                                  stream.lastMessageAt,
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: Color(0xFF9AA8A2),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                subtitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: unread > 0
                                                      ? const Color(0xFF43564D)
                                                      : const Color(0xFF8A9A92),
                                                  fontWeight: unread > 0
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                            if (unread > 0)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  left: 6,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.danger,
                                                  borderRadius:
                                                      BorderRadius.circular(99),
                                                ),
                                                child: Text(
                                                  unread > 99
                                                      ? '99+'
                                                      : '$unread',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                OnlineDot(online: controller.connected),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.connected
                        ? '实时通道已连接'
                        : (controller.connectionMessage ?? '正在连接服务器…'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF82938B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!controller.connected)
                  TextButton(
                    onPressed: controller.retryConnection,
                    child: const Text('重连'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
