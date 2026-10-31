import 'package:flutter/material.dart';
import 'package:school_link_protocol/protocol.dart';

import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

class NoticeComposerDialog extends StatefulWidget {
  const NoticeComposerDialog({super.key, required this.controller});

  final AppController controller;

  @override
  State<NoticeComposerDialog> createState() => _NoticeComposerDialogState();
}

class _NoticeComposerDialogState extends State<NoticeComposerDialog> {
  final _titleController = TextEditingController(text: '班级通知');
  final _textController = TextEditingController();
  String _closeMode = closeModeManual;
  int _seconds = defaultAutoCloseSeconds;
  bool _sound = true;
  bool _allClasses = false;
  bool _sending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入通知内容')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final title = _titleController.text.trim().isEmpty
          ? '班级通知'
          : _titleController.text.trim();
      await widget.controller.sendNotice(
        title: title,
        text: text,
        closeMode: _closeMode,
        autoCloseSec: _seconds,
        sound: _sound,
        allClasses: _allClasses,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = widget.controller.currentStream;
    final streamTitle = stream == null
        ? '当前班级'
        : (stream.className.isNotEmpty ? stream.className : classTitle(stream.classId));
    final manyClasses = widget.controller.streams.length > 1;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.campaign_rounded, color: AppColors.amber),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '发送全屏通知',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '教室大屏会立即全屏展示，普通聊天不会全屏。',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF70827A)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _titleController,
                maxLength: maxTitleLength,
                decoration: const InputDecoration(
                  labelText: '标题',
                  counterText: '',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _textController,
                minLines: 4,
                maxLines: 8,
                maxLength: maxTextLength,
                decoration: const InputDecoration(
                  labelText: '通知内容',
                  hintText: '例如：明天数学课带课本和练习册。',
                  alignLabelWithHint: true,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '关闭方式',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: closeModeManual,
                    label: Text('手动确认'),
                    icon: Icon(Icons.pan_tool_alt_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: closeModeAuto,
                    label: Text('自动关闭'),
                    icon: Icon(Icons.timer_outlined, size: 18),
                  ),
                ],
                selected: {_closeMode},
                onSelectionChanged: _sending
                    ? null
                    : (value) => setState(() => _closeMode = value.first),
                showSelectedIcon: false,
              ),
              if (_closeMode == closeModeAuto) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('显示时长', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: _seconds.toDouble(),
                        min: 5,
                        max: 120,
                        divisions: 23,
                        label: '$_seconds 秒',
                        onChanged: _sending
                            ? null
                            : (value) => setState(() => _seconds = value.round()),
                      ),
                    ),
                    Text('$_seconds 秒', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _sound,
                onChanged: _sending ? null : (value) => setState(() => _sound = value),
                title: const Text('播放提示音', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '全屏通知到达时在大屏播放提示音',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              if (manyClasses)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allClasses,
                  onChanged: _sending ? null : (value) => setState(() => _allClasses = value),
                  title: const Text('发送给全部任教班级', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '将同时发送到 ${widget.controller.streams.length} 个班级',
                    style: const TextStyle(fontSize: 12),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '发送范围：$streamTitle',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF7B8C84)),
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '通知会永久保留在教室端通知历史中。',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF8A9A92)),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _sending ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('发送通知'),
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

Future<void> showNoticeComposer(BuildContext context, AppController controller) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => NoticeComposerDialog(controller: controller),
  );
}
