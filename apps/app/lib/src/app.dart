import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_scope.dart';
import 'services/platform_service.dart';
import 'state/app_controller.dart';
import 'ui/motion.dart';
import 'ui/notice/notice_overlay.dart';
import 'ui/onboarding/classroom_reconnect_page.dart';
import 'ui/onboarding/onboarding_page.dart';
import 'ui/onboarding/teacher_auth_page.dart';
import 'ui/shell/classroom_shell.dart';
import 'ui/shell/teacher_shell.dart';
import 'ui/theme.dart';
import 'ui/widgets/window_title_bar.dart';

class SchoolLinkApp extends StatelessWidget {
  const SchoolLinkApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: '校联 SchoolLink',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final page = switch (controller.phase) {
      AppPhase.loading => const _LoadingPage(),
      AppPhase.onboarding => OnboardingPage(controller: controller),
      AppPhase.teacherAuth => TeacherAuthPage(controller: controller),
      AppPhase.teacherHome => TeacherShell(controller: controller),
      AppPhase.classroomHome => ClassroomShell(controller: controller),
      AppPhase.reconnect => ClassroomReconnectPage(controller: controller),
    };
    final notice = controller.activeNotice;
    final switcher = AnimatedSwitcher(
      duration: AppMotion.page,
      switchInCurve: AppMotion.emphasized,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
          reverseCurve: AppMotion.exit,
        );
        final slide = Tween<Offset>(
          begin: const Offset(0.02, 0),
          end: Offset.zero,
        ).animate(curved);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey(controller.phase), child: page),
    );
    Widget content = Stack(
      children: [
        Positioned.fill(child: switcher),
        if (notice != null)
          NoticeOverlay(controller: controller, message: notice),
      ],
    );
    if (platform.canCustomWindow && notice == null) {
      content = Column(
        children: [
          const WindowTitleBar(),
          Expanded(child: content),
        ],
      );
    }
    return content;
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(
                Icons.school_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '校联 SchoolLink',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 12),
            const Text(
              '正在连接学校服务器…',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF7B8C84)),
            ),
          ],
        ),
      ),
    );
  }
}
