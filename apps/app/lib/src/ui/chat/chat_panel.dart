import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:school_link_protocol/protocol.dart';

import '../../state/app_controller.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'message_tile.dart';
import 'notice_composer.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.controller,
    required this.stream,
    required this.isClassroomView,
    this.onBack,
    this.enableHero = false,
  });

  final AppController controller;
  final StreamInfo stream;
  final bool isClassroomView;
  final VoidCallback? onBack;
  final bool enableHero;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.markStreamRead(widget.stream.id);
    });
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream.id != widget.stream.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.markStreamRead(widget.stream.id);
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    _textController.clear();
    try {
      await widget.controller.sendChat(text);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _focusNode.requestFocus();
      }
    }
  }

  Future<void> _pickFiles() async {
    try {
      final files = await FilePicker.pickFiles(dialogTitle: '选择要发送的文件');
      if (files.isEmpty) return;
      await widget.controller.sendFiles(files: files, allClasses: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('选择文件失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final stream = widget.stream;
    final messages = controller.messagesFor(stream.id);
    final online = widget.isClassroomView
        ? controller.onlineTeacher(stream.teacherId)
        : controller.onlineClass(stream.classId);
    final title = widget.isClassroomView
        ? (stream.teacherName.isEmpty ? '老师' : stream.teacherName)
        : (stream.className.isEmpty
              ? classTitle(stream.classId)
              : stream.className);
    final subtitle = online ? '在线' : '当前离线';
    if (controller.unreadFor(stream.id) > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.markStreamRead(stream.id);
      });
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              if (widget.onBack != null) ...[
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: '返回',
                ),
                const SizedBox(width: 4),
              ],
              if (widget.enableHero)
                Hero(
                  tag: 'stream-avatar-${stream.id}',
                  child: Material(
                    type: MaterialType.transparency,
                    child: Avatar(
                      name: title,
                      size: 42,
                      color: widget.isClassroomView ? null : AppColors.primary,
                    ),
                  ),
                )
              else
                Avatar(
                  name: title,
                  size: 42,
                  color: widget.isClassroomView ? null : AppColors.primary,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        OnlineDot(online: online, size: 7),
                        const SizedBox(width: 5),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF7C8C85),
                          ),
                        ),
                        if (controller.connected) ...[
                          const SizedBox(width: 10),
                          const Text(
                            '实时通道已连接',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF9AA8A2),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.isClassroomView)
                IconButton(
                  onPressed: () => _openHistory(context, controller),
                  icon: const Icon(Icons.history_rounded),
                  tooltip: '全部通知历史',
                ),
            ],
          ),
        ),
        if (controller.error != null)
          Container(
            width: double.infinity,
            color: AppColors.danger.withValues(alpha: 0.07),
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 17,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    controller.error!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.danger,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: controller.clearError,
                  icon: const Icon(Icons.close_rounded, size: 17),
                ),
              ],
            ),
          ),
        if (controller.busy)
          Container(
            width: double.infinity,
            color: AppColors.primary.withValues(alpha: 0.06),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    controller.busyText ?? '正在处理…',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: messages.isEmpty
              ? EmptyState(
                  icon: widget.isClassroomView
                      ? Icons.forum_outlined
                      : Icons.mark_unread_chat_alt_outlined,
                  title: '还没有消息',
                  message: widget.isClassroomView
                      ? '老师发来的通知、消息和文件会显示在这里。'
                      : '发布通知或发送文件，教室大屏会立即收到。',
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    return AnimatedMessageEntry(
                      key: ValueKey(message.id),
                      child: MessageTile(
                        controller: controller,
                        message: message,
                        isClassroomView: widget.isClassroomView,
                      ),
                    );
                  },
                ),
        ),
        _Composer(
          controller: controller,
          isClassroomView: widget.isClassroomView,
          textController: _textController,
          focusNode: _focusNode,
          sending: _sending,
          onSend: _send,
          onAttach: widget.isClassroomView ? null : _pickFiles,
          onNotice: widget.isClassroomView
              ? null
              : () => showNoticeComposer(context, controller),
        ),
      ],
    );
  }

  void _openHistory(BuildContext context, AppController controller) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoticeHistoryPage(controller: controller),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isClassroomView,
    required this.textController,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    this.onAttach,
    this.onNotice,
  });

  final AppController controller;
  final bool isClassroomView;
  final TextEditingController textController;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback? onAttach;
  final VoidCallback? onNotice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (onAttach != null)
              IconButton(
                onPressed: sending ? null : onAttach,
                icon: const Icon(Icons.attach_file_rounded),
                tooltip: '发送文件',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF0F4F2),
                  foregroundColor: AppColors.primary,
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: textController,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: isClassroomView ? '回复老师…' : '输入消息…',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (onNotice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: FilledButton.tonalIcon(
                  onPressed: sending ? null : onNotice,
                  icon: const Icon(Icons.campaign_rounded, size: 18),
                  label: const Text('通知'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    backgroundColor: AppColors.amber.withValues(alpha: 0.16),
                    foregroundColor: const Color(0xFF8B651C),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              tooltip: '发送',
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoticeHistoryPage extends StatelessWidget {
  const NoticeHistoryPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final notices = controller.allNotices;
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知历史'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: notices.isEmpty
          ? const EmptyState(
              icon: Icons.campaign_outlined,
              title: '还没有通知',
              message: '老师发送的全屏通知会集中保存在这里。',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: notices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final message = notices[index];
                final className =
                    parseClassId(message.classId)?.title ??
                    controller.currentClassTitle;
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => controller.previewNotice(message),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.amber.withValues(
                                    alpha: 0.16,
                                  ),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  className,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF8B651C),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                message.senderName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF7C8C85),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                formatFullTime(message.createdAt),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF9AA8A2),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            message.title.trim().isEmpty
                                ? '班级通知'
                                : message.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (message.text.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              message.text,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: Color(0xFF5F7068),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(
                                Icons.fullscreen_rounded,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '点击全屏查看',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class AnimatedMessageEntry extends StatefulWidget {
  const AnimatedMessageEntry({super.key, required this.child});

  final Widget child;

  @override
  State<AnimatedMessageEntry> createState() => _AnimatedMessageEntryState();
}

class _AnimatedMessageEntryState extends State<AnimatedMessageEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.standard)
      ..forward();
    final curve = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.emphasized,
    );
    _opacity = curve;
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(curve);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
