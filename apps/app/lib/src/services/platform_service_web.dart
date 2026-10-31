import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:school_link_protocol/protocol.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web/web.dart' as web;

class SavedFile {
  const SavedFile({required this.path, required this.displayName});

  final String path;
  final String displayName;
}

final PlatformService platform = PlatformService();

class PlatformService {
  final ValueNotifier<bool> windowMaximized = ValueNotifier<bool>(false);

  bool get canHostHub => false;

  bool get canCustomWindow => false;

  bool get canAutoStart => false;

  bool get isDesktop => false;

  String get name => 'Web';

  Future<void> init() async {}

  Future<void> minimizeWindow() async {}

  Future<void> toggleMaximizeWindow() async {}

  Future<void> startWindowDragging() async {}

  Future<void> closeWindowToTray() async {}

  Future<String> machineName() async => '浏览器教室';

  Future<SavedFile> saveReceivedFile({
    required Uint8List bytes,
    required String fileName,
    required String className,
    required String teacherName,
  }) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = sanitizeFileName(fileName);
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return SavedFile(path: '', displayName: fileName);
  }

  Future<void> openFile(String path) async {}

  Future<void> revealFile(String path) async {}

  Future<void> setNoticeFullscreen(bool enabled) async {
    try {
      if (enabled) {
        web.document.documentElement?.requestFullscreen().toDart.ignore();
      } else {
        web.document.exitFullscreen().toDart.ignore();
      }
    } catch (_) {}
  }

  Future<bool> isAutoStartEnabled() async => false;

  Future<void> setAutoStart(bool enabled) async {}

  Future<void> keepAwake(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  Future<void> setFullscreen(bool enabled) => setNoticeFullscreen(enabled);

  Future<bool> get isFullscreen async => false;
}
