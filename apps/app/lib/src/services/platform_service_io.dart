import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:school_link_protocol/protocol.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_profile.dart';

class SavedFile {
  const SavedFile({required this.path, required this.displayName});

  final String path;
  final String displayName;
}

final PlatformService platform = PlatformService();

class PlatformService with WindowListener {
  Rect? _previousBounds;
  TrayIcon? _trayIcon;
  // Kept alive so native menu handles remain valid while the tray is visible.
  // ignore: unused_field
  Menu? _trayMenu;
  // ignore: unused_field
  List<MenuItem> _trayItems = const [];
  bool _quitting = false;
  bool _trayReady = false;

  final ValueNotifier<bool> windowMaximized = ValueNotifier<bool>(false);

  bool get canHostHub => Platform.isWindows;

  bool get canAutoStart => Platform.isWindows;

  bool get canCustomWindow => Platform.isWindows;

  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  String get name {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    return 'Desktop';
  }

  Future<void> init() async {
    if (!Platform.isWindows) return;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    final options = WindowOptions(
      size: const Size(1280, 820),
      minimumSize: const Size(980, 680),
      center: true,
      title: appProfile.isEmpty
          ? '校联 SchoolLink'
          : '校联 SchoolLink · $appProfile',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    try {
      windowMaximized.value = await windowManager.isMaximized();
    } catch (_) {}
    await _initTray();
    await windowManager.setPreventClose(_trayReady);
  }

  Future<void> _initTray() async {
    try {
      final tray = TrayIcon.create();
      if (tray == null) return;
      final icon = ImageAsset.fromAsset('assets/brand/app_icon.png');
      if (icon == null) {
        tray.dispose();
        return;
      }
      tray.icon = icon;
      tray.setTooltip('校联 SchoolLink');

      final menu = Menu.create();
      if (menu != null) {
        final show = MenuItem.createWithLabelAndType(
          '打开校联',
          MenuItemType.normal,
        );
        final hide = MenuItem.createWithLabelAndType(
          '隐藏到托盘',
          MenuItemType.normal,
        );
        final exit = MenuItem.createWithLabelAndType(
          '退出校联',
          MenuItemType.normal,
        );
        show?.addListener((event) {
          if (event is MenuItemClickedEvent) unawaited(_showWindow());
        });
        hide?.addListener((event) {
          if (event is MenuItemClickedEvent) unawaited(windowManager.hide());
        });
        exit?.addListener((event) {
          if (event is MenuItemClickedEvent) unawaited(_quitApplication());
        });
        menu.addItem(show);
        menu.addItem(hide);
        menu.addSeparator();
        menu.addItem(exit);
        _trayItems = [?show, ?hide, ?exit];
        _trayMenu = menu;
        tray.setContextMenu(menu);
        tray.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      }

      tray.addListener((event) {
        if (event is TrayIconClickedEvent ||
            event is TrayIconDoubleClickedEvent) {
          unawaited(_showWindow());
        }
      });
      tray.setVisible(true);
      _trayIcon = tray;
      _trayReady = true;
    } catch (error) {
      debugPrint('Tray init failed: $error');
    }
  }

  Future<void> _showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  Future<void> _quitApplication() async {
    if (_quitting) return;
    _quitting = true;
    try {
      _trayIcon?.setVisible(false);
      _trayIcon?.dispose();
    } catch (_) {}
    _trayIcon = null;
    _trayMenu = null;
    _trayItems = const [];
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  @override
  void onWindowClose() {
    if (_quitting || !_trayReady) return;
    unawaited(windowManager.hide());
    final tray = _trayIcon;
    if (tray != null) {
      tray.setTooltip('校联 SchoolLink · 正在托盘中运行');
    }
  }

  @override
  void onWindowMaximize() => windowMaximized.value = true;

  @override
  void onWindowUnmaximize() => windowMaximized.value = false;

  @override
  void onWindowRestore() => windowMaximized.value = false;

  Future<void> minimizeWindow() async {
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  Future<void> toggleMaximizeWindow() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      windowMaximized.value = await windowManager.isMaximized();
    } catch (_) {}
  }

  Future<void> startWindowDragging() async {
    try {
      await windowManager.startDragging();
    } catch (_) {}
  }

  Future<void> closeWindowToTray() async {
    try {
      await windowManager.close();
    } catch (_) {}
  }

  Future<String> machineName() async {
    try {
      final name = Platform.localHostname.trim();
      return name.isEmpty ? '本机教室' : name;
    } catch (_) {
      return '本机教室';
    }
  }

  Future<SavedFile> saveReceivedFile({
    required Uint8List bytes,
    required String fileName,
    required String className,
    required String teacherName,
  }) async {
    Directory baseDir;
    if (Platform.isWindows) {
      final downloads = await getDownloadsDirectory();
      baseDir = downloads ?? await getApplicationDocumentsDirectory();
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final folder = Directory(
      p.join(
        baseDir.path,
        '校联',
        sanitizeFileName(className),
        date,
        sanitizeFileName(teacherName),
      ),
    );
    await folder.create(recursive: true);
    final safeName = sanitizeFileName(fileName);
    var target = File(p.join(folder.path, safeName));
    if (await target.exists()) {
      final ext = p.extension(safeName);
      final stem = p.basenameWithoutExtension(safeName);
      var index = 1;
      while (await target.exists()) {
        target = File(p.join(folder.path, '$stem ($index)$ext'));
        index += 1;
      }
    }
    await target.writeAsBytes(bytes, flush: true);
    return SavedFile(path: target.path, displayName: target.path);
  }

  Future<void> openFile(String path) async {
    if (path.isEmpty) return;
    if (Platform.isWindows ||
        Platform.isAndroid ||
        Platform.isLinux ||
        Platform.isMacOS) {
      await OpenFilex.open(path);
    }
  }

  Future<void> revealFile(String path) async {
    if (path.isEmpty) return;
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', path]);
      return;
    }
    await openFile(path);
  }

  Future<void> setNoticeFullscreen(bool enabled) async {
    if (Platform.isWindows) {
      try {
        if (enabled) {
          await _showWindow();
          _previousBounds = await windowManager.getBounds();
          await windowManager.setAlwaysOnTop(true);
          await windowManager.setFullScreen(true);
        } else {
          await windowManager.setFullScreen(false);
          await windowManager.setAlwaysOnTop(false);
          if (_previousBounds != null) {
            await windowManager.setBounds(_previousBounds!);
          }
        }
      } catch (_) {}
    } else if (Platform.isAndroid) {
      try {
        await SystemChrome.setEnabledSystemUIMode(
          enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        );
      } catch (_) {}
    }
  }

  Future<bool> isAutoStartEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        'SchoolLink',
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> setAutoStart(bool enabled) async {
    if (!Platform.isWindows) return;
    try {
      if (enabled) {
        await Process.run('reg', [
          'add',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          'SchoolLink',
          '/t',
          'REG_SZ',
          '/d',
          '"${Platform.resolvedExecutable}"',
          '/f',
        ]);
      } else {
        await Process.run('reg', [
          'delete',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          'SchoolLink',
          '/f',
        ]);
      }
    } catch (_) {}
  }

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

  Future<bool> get isFullscreen async {
    if (!Platform.isWindows) return false;
    try {
      return await windowManager.isFullScreen();
    } catch (_) {
      return false;
    }
  }
}
