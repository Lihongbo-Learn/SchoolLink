import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:school_link_hub/hub.dart';
import 'package:school_link_protocol/protocol.dart';

final HubRuntime hubRuntime = HubRuntime();

class HubRuntime extends ChangeNotifier {
  HubServer? _server;
  HubStore? _store;
  bool _starting = false;
  String? _error;
  List<String> _urls = const [];
  String? _dataDir;
  String? _webRoot;
  int _port = hubHttpPort;

  bool get supported => Platform.isWindows;

  bool get running => _server?.running ?? false;

  bool get starting => _starting;

  String? get error => _error;

  List<String> get urls => _urls;

  String get localUrl => 'http://127.0.0.1:$_port';

  String? get dataDir => _dataDir;

  String? get webRoot => _webRoot;

  bool get hasWebBuild =>
      _webRoot != null && File(p.join(_webRoot!, 'index.html')).existsSync();

  Future<void> start() async {
    if (running || _starting) return;
    _starting = true;
    _error = null;
    notifyListeners();
    try {
      _dataDir ??= p.join(
        Platform.environment['LOCALAPPDATA'] ?? Directory.current.path,
        'SchoolLinkHub',
      );
      _webRoot ??= _findWebRoot();
      await Directory(_dataDir!).create(recursive: true);
      _store = await HubStore.open(dataDir: _dataDir!);
      final server = HubServer(
        store: _store!,
        port: hubHttpPort,
        webRoot: _webRoot,
        enableDiscovery: true,
      );
      await server.start();
      _server = server;
      _port = server.actualPort;
      _urls = await server.localUrls();
    } catch (e) {
      _error = 'Hub 启动失败：$e';
      await _server?.stop();
      _server = null;
      await _store?.close();
      _store = null;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_starting) return;
    await _server?.stop();
    _server = null;
    await _store?.close();
    _store = null;
    _urls = const [];
    notifyListeners();
  }

  String? _findWebRoot() {
    final candidates = <String>[
      p.join(File(Platform.resolvedExecutable).parent.path, 'web'),
      p.join(Directory.current.path, 'build', 'web'),
      p.join(Directory.current.path, 'apps', 'app', 'build', 'web'),
      p.join(Directory.current.path, 'web'),
    ];
    for (final candidate in candidates) {
      if (File(p.join(candidate, 'index.html')).existsSync()) return candidate;
    }
    return null;
  }

  @override
  void dispose() {
    _server?.stop();
    _store?.close();
    super.dispose();
  }
}
