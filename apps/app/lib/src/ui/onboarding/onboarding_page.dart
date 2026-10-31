import 'package:flutter/material.dart';
import 'package:school_link_protocol/protocol.dart';

import '../../state/app_controller.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/hub_connector.dart';
import 'teacher_auth_form.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  String? _selectedMode;
  int _grade = 1;
  int _classNo = 9;
  bool _confirmed = false;
  bool _busy = false;
  String? _error;

  Future<void> _lockClassroom() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      if (widget.controller.hubUrl.isEmpty) {
        throw '请先填写并连接学校服务器';
      }
      if (!_confirmed) {
        throw '请先确认年级和班级无误';
      }
      await widget.controller.setupClassroom(
        hubUrlInput: widget.controller.hubUrl,
        gradeInput: _grade,
        classNumber: _classNo,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 980;
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(wide: wide),
                    const SizedBox(height: 28),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                HubConnector(controller: widget.controller),
                                const SizedBox(height: 20),
                                _modeSection(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(flex: 6, child: _animatedRightColumn()),
                        ],
                      )
                    else ...[
                      HubConnector(controller: widget.controller),
                      const SizedBox(height: 20),
                      _modeSection(),
                      const SizedBox(height: 20),
                      _animatedRightColumn(),
                    ],
                    const SizedBox(height: 28),
                    const Center(
                      child: Text(
                        '校联 SchoolLink · 数据仅在校内局域网传输',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8A9A92),
                        ),
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

  Widget _modeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            '选择本机用途',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        ModeCard(
          selected: _selectedMode == 'classroom',
          title: '教室模式',
          subtitle: '用于教室大屏：接收通知、自动收文件、回复老师。选择后不可更改。',
          icon: Icons.tv_rounded,
          onTap: () => setState(() => _selectedMode = 'classroom'),
        ),
        const SizedBox(height: 12),
        ModeCard(
          selected: _selectedMode == 'teacher',
          title: '教师模式',
          subtitle: '用于老师手机或电脑：选择任教班级、发通知、发文件、查看回复。',
          icon: Icons.co_present_rounded,
          onTap: () => setState(() => _selectedMode = 'teacher'),
        ),
      ],
    );
  }

  Widget _animatedRightColumn() {
    return AnimatedSwitcher(
      duration: AppMotion.standard,
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.02, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey('mode-${_selectedMode ?? 'none'}'),
        child: _rightColumn(),
      ),
    );
  }

  Widget _rightColumn() {
    if (_selectedMode == 'teacher') {
      return TeacherAuthForm(
        controller: widget.controller,
        initialRegister: true,
      );
    }
    if (_selectedMode == 'classroom') {
      return _classroomCard();
    }
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '先连接服务器，再选择用途',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '校联使用学校内的一台常开电脑作为 Hub。教室端和教师端都会自动发现它；网页版则直接打开 Hub 地址。',
            style: TextStyle(
              fontSize: 13.5,
              color: Color(0xFF6B7C74),
              height: 1.7,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 20,
                  color: AppColors.amber,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '教室模式锁定后没有切换入口；卸载重装才能重新选择。建议由老师或管理员在教室电脑上完成首次设置。',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: Color(0xFF5C6D65),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _classroomCard() {
    final title = '${gradeName(_grade)}$_classNo班';
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '设置教室端',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '选择一个大屏所属的年级和班级。',
            style: TextStyle(fontSize: 13, color: Color(0xFF70827A)),
          ),
          const SizedBox(height: 18),
          const Text(
            '年级',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (final grade in gradeNumbers)
                ButtonSegment(value: grade, label: Text(gradeName(grade))),
            ],
            selected: {_grade},
            onSelectionChanged: _busy
                ? null
                : (value) => setState(() => _grade = value.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '班级',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final number in classNumbers)
                ChoiceChip(
                  label: Text('$number班'),
                  selected: _classNo == number,
                  onSelected: _busy
                      ? null
                      : (value) => setState(() => _classNo = number),
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: _classNo == number
                        ? Colors.white
                        : const Color(0xFF35473F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.amber,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '不可逆设置',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '本机将锁定为「$title」教室端，界面内无法切换班级或模式。卸载重装或清除应用数据后才能重新选择。',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: Color(0xFF6C5A32),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _confirmed,
            onChanged: _busy
                ? null
                : (value) => setState(() => _confirmed = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              '我确认本机为「$title」教室大屏',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy || widget.controller.hubUrl.isEmpty
                  ? null
                  : _lockClassroom,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.lock_rounded),
              label: Text('锁定为$title教室端'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.school_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '校联',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: Color(0xFF13251F),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (wide)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'SchoolLink',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '校园局域网 · 文件共享 · 大屏通知',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF65776F),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
