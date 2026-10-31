import 'package:flutter/material.dart';
import 'package:school_link_protocol/protocol.dart';

import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/hub_connector.dart';

class ClassroomReconnectPage extends StatefulWidget {
  const ClassroomReconnectPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ClassroomReconnectPage> createState() => _ClassroomReconnectPageState();
}

class _ClassroomReconnectPageState extends State<ClassroomReconnectPage> {
  bool _busy = false;
  String? _error;

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.reconnectClassroom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classId = widget.controller.classId;
    final title = classId == null ? '教室端' : (parseClassId(classId)?.title ?? classId);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF4F8F5), Color(0xFFEAF2EE)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tv_rounded, size: 30, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Text(
                          '$title · 教室端',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '教室模式已锁定，不能更换年级、班级或切换为教师模式。',
                      style: TextStyle(color: Color(0xFF6B7C74)),
                    ),
                    const SizedBox(height: 20),
                    HubConnector(controller: widget.controller),
                    const SizedBox(height: 20),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '重新绑定教室端',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '服务器上的登录信息可能已重置。重新连接会以本机身份重新绑定「$title」，不会改变已锁定的班级。',
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: Color(0xFF6B7C74),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.tag_rounded, size: 16, color: Color(0xFF82938B)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '设备标识：${widget.controller.installId ?? '-'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF82938B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(color: AppColors.danger, fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy || widget.controller.hubUrl.isEmpty
                                  ? null
                                  : _retry,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                              label: const Text('重新连接并进入教室端'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
