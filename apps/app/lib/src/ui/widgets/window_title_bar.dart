import 'package:flutter/material.dart';
import 'package:school_link_protocol/protocol.dart';

import '../../services/platform_service.dart';
import '../motion.dart';
import '../theme.dart';

class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (!platform.canCustomWindow) return const SizedBox.shrink();
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A1B22), Color(0xFF103F35)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(bottom: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Row(
        children: [
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.basic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => platform.startWindowDragging(),
                onDoubleTap: () => platform.toggleMaximizeWindow(),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(
                          Icons.school_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '校联',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'SchoolLink',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          appVersion,
                          style: const TextStyle(
                            color: AppColors.amber,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _CaptionButton(
            icon: Icons.remove_rounded,
            tooltip: '最小化',
            onPressed: platform.minimizeWindow,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: platform.windowMaximized,
            builder: (context, maximized, _) => _CaptionButton(
              icon: maximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              tooltip: maximized ? '还原' : '最大化',
              onPressed: platform.toggleMaximizeWindow,
            ),
          ),
          _CaptionButton(
            icon: Icons.close_rounded,
            tooltip: '关闭到托盘（后台继续运行）',
            close: true,
            onPressed: platform.closeWindowToTray,
          ),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.close = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool close;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.close
        ? const Color(0xFFC24848)
        : Colors.white.withValues(alpha: 0.12);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.enter,
            width: 46,
            height: 38,
            color: _hover ? hoverColor : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 16,
              color: _hover
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}
