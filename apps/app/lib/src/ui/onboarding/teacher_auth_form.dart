import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TeacherAuthForm extends StatefulWidget {
  const TeacherAuthForm({
    super.key,
    required this.controller,
    this.initialRegister = true,
    this.compact = false,
  });

  final AppController controller;
  final bool initialRegister;
  final bool compact;

  @override
  State<TeacherAuthForm> createState() => _TeacherAuthFormState();
}

class _TeacherAuthFormState extends State<TeacherAuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _codeController = TextEditingController();
  final _selectedClasses = <String>{};
  late bool _register;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _register = widget.initialRegister;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_register && _selectedClasses.isEmpty) {
      setState(() => _error = '请至少选择一个任教班级');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_register) {
        await widget.controller.registerTeacher(
          name: _nameController.text,
          pin: _pinController.text,
          registrationCode: _codeController.text,
          classIds: _selectedClasses.toList(),
        );
      } else {
        await widget.controller.loginTeacher(
          name: _nameController.text,
          pin: _pinController.text,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requiresCode = widget.controller.hubInfo?.registrationCodeRequired ?? true;
    return SectionCard(
      child: Form(
        key: _formKey,
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
                        '教师账号',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '姓名是教室端看到的称呼，PIN 用于保护账号。',
                        style: TextStyle(fontSize: 13, color: Color(0xFF70827A)),
                      ),
                    ],
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('注册')),
                    ButtonSegment(value: false, label: Text('登录')),
                  ],
                  selected: {_register},
                  onSelectionChanged: _busy
                      ? null
                      : (value) => setState(() => _register = value.first),
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: '教师姓名',
                hintText: '例如 张老师',
                prefixIcon: Icon(Icons.person_outline_rounded),
                counterText: '',
              ),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return '请输入教师姓名';
                if (v.length > 20) return '姓名不能超过 20 个字符';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _pinController,
              obscureText: _obscure,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: 'PIN（4–6 位数字）',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (!RegExp(r'^\d{4,6}$').hasMatch(v)) return 'PIN 必须为 4–6 位数字';
                return null;
              },
            ),
            if (_register) ...[
              if (requiresCode) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: '学校注册码',
                    hintText: '向学校管理员获取',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  validator: (value) =>
                      (value?.trim().isEmpty ?? true) ? '请输入学校注册码' : null,
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                '选择任教班级',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                '注册后仍可在设置中修改；教室端会显示这些班级的老师。',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF70827A)),
              ),
              const SizedBox(height: 10),
              ClassPicker(
                selected: _selectedClasses,
                onChanged: (value) => setState(() {
                  _selectedClasses
                    ..clear()
                    ..addAll(value);
                }),
                enabled: !_busy,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_register ? Icons.person_add_alt_1_rounded : Icons.login_rounded),
                label: Text(_register ? '注册并进入教师端' : '登录教师端'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
