import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:school_link_hub/hub.dart';
import 'package:school_link_protocol/protocol.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('data', help: 'Hub 数据目录')
    ..addOption('port', defaultsTo: '$hubHttpPort', help: 'HTTP/WS 端口')
    ..addOption('web-root', help: 'Flutter Web 构建产物目录')
    ..addOption('name', help: 'Hub 名称')
    ..addFlag('discovery', defaultsTo: true, help: '启用 UDP 自动发现')
    ..addFlag('firewall', defaultsTo: true, help: 'Windows 启动时自动申请防火墙放行')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(arguments);
  if (args['help'] as bool) {
    print('校联 Hub\n${parser.usage}');
    return;
  }

  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final time = record.time.toIso8601String().substring(11, 19);
    print('[$time] ${record.level.name}: ${record.message}');
  });

  final env = Platform.environment;
  final defaultData = Platform.isWindows
      ? p.join(env['LOCALAPPDATA'] ?? Directory.current.path, 'SchoolLinkHub')
      : p.join(env['HOME'] ?? Directory.current.path, '.schoollink-hub');
  final dataDir = (args['data'] as String?)?.trim().isNotEmpty == true
      ? args['data'] as String
      : defaultData;
  final port = int.tryParse(args['port'] as String) ?? hubHttpPort;
  final webRoot = (args['web-root'] as String?)?.trim().isNotEmpty == true
      ? args['web-root'] as String
      : p.join(Directory.current.path, 'web');

  final store = await HubStore.open(
    dataDir: dataDir,
    name: (args['name'] as String?)?.trim().isNotEmpty == true ? args['name'] as String : null,
  );
  final server = HubServer(
    store: store,
    port: port,
    webRoot: Directory(webRoot).existsSync() ? webRoot : null,
    enableDiscovery: args['discovery'] as bool,
    enableFirewall: args['firewall'] as bool,
  );

  try {
    await server.start();
  } catch (error) {
    stderr.writeln('Hub 启动失败：$error');
    await store.close();
    exitCode = 1;
    return;
  }

  print('');
  print('  校联 Hub 已启动');
  print('  数据目录：$dataDir');
  print('  默认管理员 PIN：246810（请在管理台修改）');
  print('  学校注册码：${store.config.registrationCode}');
  print('  Web 目录：${Directory(webRoot).existsSync() ? webRoot : "未部署"}');
  for (final url in await server.localUrls()) {
    print('  Web 地址：$url');
  }
  print('');

  final completer = Completer<void>();
  Future<void> shutdown() async {
    if (completer.isCompleted) return;
    print('正在关闭 Hub...');
    await server.stop();
    await store.close();
    completer.complete();
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }
  await completer.future;
}
