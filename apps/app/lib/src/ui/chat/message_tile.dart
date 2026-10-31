import 'package:flutter/material.dart';
import 'package:school_link_protocol/protocol.dart';

import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.controller,
    required this.message,
    required this.isClassroomView,
  });

  final AppController controller;
  final Message message;
  final bool isClassroomView;

  bool get _mine =>
      isClassroomView ? message.fromClassroom : message.fromTeacher;

  @override
  Widget build(BuildContext context) {
    if (message.isNotice) {
      return _NoticeMessageCard(
        controller: controller,
        message: message,
        isClassroomView: isClassroomView,
      );
    }
    if (message.isFile) {
      return _FileMessageCard(
        controller: controller,
        message: message,
        isClassroomView: isClassroomView,
        mine: _mine,
      );
    }
    return _ChatBubble(
      controller: controller,
      message: message,
      isClassroomView: isClassroomView,
      mine: _mine,
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.controller,
    required this.message,
    required this.isClassroomView,
    required this.mine,
  });

  final AppController controller;
  final Message message;
  final bool isClassroomView;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final time = formatClock(message.createdAt);
    final state = controller.sendStateOf(message.id);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    message.senderName.isEmpty
                        ? (isClassroomView ? '老师' : '教室端')
                        : message.senderName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7C8C85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: mine ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine ? 18 : 5),
                    bottomRight: Radius.circular(mine ? 5 : 18),
                  ),
                  border: mine
                      ? null
                      : Border.all(color: const Color(0xFFE4EBE7)),
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: mine ? Colors.white : const Color(0xFF24352E),
                    fontSize: 15,
                    height: 1.55,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9AA8A2)),
                    ),
                    if (mine && state != null) ...[
                      const SizedBox(width: 5),
                      _SendStateIcon(state: state, controller: controller, message: message),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendStateIcon extends StatelessWidget {
  const _SendStateIcon({
    required this.state,
    required this.controller,
    required this.message,
  });

  final String state;
  final AppController controller;
  final Message message;

  @override
  Widget build(BuildContext context) {
    if (state == MessageSendState.sending.name) {
      return const SizedBox(
        width: 11,
        height: 11,
        child: CircularProgressIndicator(strokeWidth: 1.4, color: Color(0xFF8A9A92)),
      );
    }
    if (state == MessageSendState.failed.name) {
      return const Tooltip(
        message: '发送失败，请检查连接后重试',
        child: Icon(Icons.error_outline_rounded, size: 14, color: AppColors.danger),
      );
    }
    final delivered = controller.deliveryCount(message.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.done_all_rounded, size: 14, color: AppColors.success),
        if (delivered > 0) ...[
          const SizedBox(width: 3),
          Text(
            '已送达 $delivered',
            style: const TextStyle(fontSize: 10.5, color: AppColors.success),
          ),
        ],
      ],
    );
  }
}

class _NoticeMessageCard extends StatelessWidget {
  const _NoticeMessageCard({
    required this.controller,
    required this.message,
    required this.isClassroomView,
  });

  final AppController controller;
  final Message message;
  final bool isClassroomView;

  @override
  Widget build(BuildContext context) {
    final mine = isClassroomView ? message.fromClassroom : message.fromTeacher;
    final title = message.title.trim().isEmpty ? '班级通知' : message.title.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E8),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1D79E)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.campaign_rounded, size: 14, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        '全屏通知',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  formatFullTime(message.createdAt),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9A8555)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.3),
            ),
            if (message.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                message.text,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Color(0xFF4C4331),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${message.senderName} · ${message.manualClose ? '需确认关闭' : '${message.autoCloseSec} 秒自动关闭'}',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF9A8555)),
                ),
                const Spacer(),
                if (isClassroomView)
                  TextButton.icon(
                    onPressed: () => controller.previewNotice(message),
                    icon: const Icon(Icons.fullscreen_rounded, size: 18),
                    label: const Text('全屏预览'),
                  ),
                if (mine && !isClassroomView)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.done_all_rounded, size: 15, color: AppColors.success),
                      SizedBox(width: 4),
                      Text(
                        '已发送',
                        style: TextStyle(fontSize: 11, color: AppColors.success),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FileMessageCard extends StatelessWidget {
  const _FileMessageCard({
    required this.controller,
    required this.message,
    required this.isClassroomView,
    required this.mine,
  });

  final AppController controller;
  final Message message;
  final bool isClassroomView;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final file = message.file;
    if (file == null) return const SizedBox.shrink();
    final path = controller.filePathOf(message.id);
    final downloading = controller.downloading(message.id);
    final sendState = controller.sendStateOf(message.id);
    final canOpen = path != null && path.isNotEmpty;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E8E4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.insert_drive_file_rounded, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatFileSize(file.size),
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF84948D)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (sendState == MessageSendState.sending.name)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (sendState == MessageSendState.failed.name)
                  const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18)
                else if (mine)
                  const Icon(Icons.done_all_rounded, color: AppColors.success, size: 18),
              ],
            ),
            const SizedBox(height: 10),
            if (downloading)
              const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('正在自动接收…', style: TextStyle(fontSize: 12)),
                ],
              )
            else if (isClassroomView && !mine)
              Row(
                children: [
                  Icon(
                    canOpen ? Icons.check_circle_rounded : Icons.download_rounded,
                    size: 16,
                    color: canOpen ? AppColors.success : const Color(0xFF84948D),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      canOpen ? '已自动保存' : '等待接收',
                      style: TextStyle(
                        fontSize: 12,
                        color: canOpen ? AppColors.success : const Color(0xFF84948D),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (canOpen) ...[
                    TextButton(
                      onPressed: () => controller.openMessageFile(message),
                      child: const Text('打开'),
                    ),
                    TextButton(
                      onPressed: () => controller.revealMessageFile(message),
                      child: const Text('定位'),
                    ),
                  ] else
                    TextButton(
                      onPressed: () => controller.downloadFileForMessage(message),
                      child: const Text('接收'),
                    ),
                ],
              )
            else if (canOpen)
              Row(
                children: [
                  const Icon(Icons.save_alt_rounded, size: 16, color: AppColors.success),
                  const SizedBox(width: 5),
                  const Expanded(
                    child: Text(
                      '本地文件',
                      style: TextStyle(fontSize: 12, color: AppColors.success),
                    ),
                  ),
                  TextButton(
                    onPressed: () => controller.openMessageFile(message),
                    child: const Text('打开'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
