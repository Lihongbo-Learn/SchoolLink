import 'dart:async';

import 'package:flutter/material.dart';
import 'package:school_link_protocol/protocol.dart';

import '../../state/app_controller.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/common.dart';

class NoticeOverlay extends StatefulWidget {
  const NoticeOverlay({
    super.key,
    required this.controller,
    required this.message,
  });

  final AppController controller;
  final Message message;

  @override
  State<NoticeOverlay> createState() => _NoticeOverlayState();
}

class _NoticeOverlayState extends State<NoticeOverlay>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;
  int _remaining = 0;
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this, duration: AppMotion.standard)
      ..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: AppMotion.emphasized);
    _scale = Tween<double>(begin: 0.972, end: 1).animate(_fade);
    _remaining = widget.message.autoCloseSec;
    if (!widget.message.manualClose && _remaining > 0) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remaining = (_remaining - 1).clamp(0, 999));
        if (_remaining <= 0) _ticker?.cancel();
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final queue = widget.controller.noticeQueueLength;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 760;
    final titleSize = compact ? 34.0 : (size.width > 1500 ? 64.0 : 48.0);
    final bodySize = compact ? 20.0 : (size.width > 1500 ? 38.0 : 28.0);
    final title = message.title.trim().isEmpty ? '班级通知' : message.title.trim();
    final className =
        parseClassId(message.classId)?.title ??
        widget.controller.currentClassTitle;
    final total = message.autoCloseSec <= 0 ? 1 : message.autoCloseSec;
    final progress = message.manualClose
        ? null
        : ((total - _remaining) / total).clamp(0.0, 1.0);

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(
          scale: _scale,
          child: Material(
            color: AppColors.navy,
            child: Stack(
              children: [
                Positioned(
                  top: -180,
                  right: -120,
                  child: _Glow(
                    size: 460,
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
                ),
                Positioned(
                  bottom: -200,
                  left: -160,
                  child: _Glow(
                    size: 520,
                    color: AppColors.amber.withValues(alpha: 0.12),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 24 : 64,
                      vertical: compact ? 24 : 40,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.school_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              '校联 · 班级通知',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                            const Spacer(),
                            if (queue > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '还有 $queue 条待展示',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const Spacer(flex: 2),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: AppColors.amber.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                              child: Text(
                                classInfoLabel(className, message),
                                style: const TextStyle(
                                  color: AppColors.amber,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${message.senderName} · ${formatFullTime(message.createdAt)}',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 24 : 36),
                        Text(
                          title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                            height: 1.18,
                            letterSpacing: 1,
                          ),
                        ),
                        SizedBox(height: compact ? 18 : 28),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              message.text.isEmpty ? '（无正文）' : message.text,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: bodySize,
                                height: 1.65,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (progress != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 5,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.12,
                              ),
                              valueColor: const AlwaysStoppedAnimation(
                                AppColors.amber,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            if (message.manualClose)
                              const Text(
                                '需要老师确认后关闭',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              )
                            else
                              Text(
                                '$_remaining 秒后自动关闭',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: widget.controller.dismissNotice,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.navy,
                                minimumSize: Size(compact ? 140 : 180, 56),
                                textStyle: const TextStyle(
                                  fontFamily: 'NotoSansSC',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('我知道了'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String classInfoLabel(String className, Message message) {
    final teacher = message.senderName.isEmpty ? '老师' : message.senderName;
    return '$className · $teacher';
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}
