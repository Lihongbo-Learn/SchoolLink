import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/core/app_profile.dart';
import 'src/services/platform_service.dart';
import 'src/state/app_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--profile=')) {
      appProfile = arg.substring('--profile='.length).trim();
    } else if (arg == '--profile' && i + 1 < args.length) {
      appProfile = args[i + 1].trim();
    }
  }
  SharedPreferences.setPrefix(
    'schoollink_${appProfile.isEmpty ? 'default' : appProfile}_',
  );
  try {
    await platform.init();
  } catch (error) {
    debugPrint('platform init failed: $error');
  }
  final controller = AppController();
  runApp(SchoolLinkApp(controller: controller));
  unawaited(
    controller.init().catchError((Object error, StackTrace stack) {
      debugPrint('App init failed: $error\n$stack');
    }),
  );
}
