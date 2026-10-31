import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/hub_connector.dart';
import 'teacher_auth_form.dart';

class TeacherAuthPage extends StatelessWidget {
  const TeacherAuthPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
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
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.co_present_rounded, size: 30, color: AppColors.primary),
                        SizedBox(width: 12),
                        Text(
                          '教师端登录',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '登录后选择任教班级，即可向教室发送通知和文件。',
                      style: TextStyle(color: Color(0xFF6B7C74), height: 1.6),
                    ),
                    const SizedBox(height: 22),
                    HubConnector(controller: controller),
                    const SizedBox(height: 20),
                    TeacherAuthForm(
                      controller: controller,
                      initialRegister: false,
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
