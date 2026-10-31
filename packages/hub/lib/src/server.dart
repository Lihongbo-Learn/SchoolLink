import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:school_link_protocol/protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'errors.dart';
import 'store.dart';
import 'windows_firewall.dart';

class HubConnection {
  HubConnection(this.channel);

  final WebSocketChannel channel;
  SessionSubject? subject;
  String deviceId = '';
  Timer? authTimer;
  bool closed = false;
}

class HubServer {
  HubServer({
    required this.store,
    this.port = hubHttpPort,
    this.webRoot,
    this.enableDiscovery = true,
    this.enableFirewall = true,
  });

  final HubStore store;
  final int port;
  final String? webRoot;
  final bool enableDiscovery;
  final bool enableFirewall;

  final Logger _log = Logger('school_link_hub');
  final Set<HubConnection> _connections = <HubConnection>{};
  final Map<String, List<int>> _loginFailures = <String, List<int>>{};
  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  Timer? _cleanupTimer;
  Handler? _staticHandler;
  bool _started = false;

  int get actualPort => _server?.port ?? port;

  bool get running => _started;

  Future<void> start() async {
    if (_started) return;
    final handler = _buildHandler();
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    _server!.autoCompress = true;
    _started = true;
    _log.info('Hub listening on port ${_server!.port}');
    if (enableFirewall) {
      unawaited(
        ensureWindowsFirewall(logger: _log).catchError((Object error) {
          _log.warning('Firewall provisioning failed: $error');
        }),
      );
    }
    if (enableDiscovery) {
      await _startDiscovery();
    }
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      store.cleanupExpiredFiles().catchError((Object error) {
        _log.warning('cleanup failed: $error');
      });
    });
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _cleanupTimer?.cancel();
    _discoverySocket?.close();
    _discoverySocket = null;
    for (final connection in _connections.toList()) {
      try {
        await connection.channel.sink.close(1000, 'server shutdown');
      } catch (_) {}
    }
    _connections.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<List<String>> localUrls() async {
    final result = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (ip.startsWith('169.254.')) continue;
          result.add('http://$ip:$actualPort');
        }
      }
    } catch (_) {}
    if (result.isEmpty) result.add('http://127.0.0.1:$actualPort');
    return result;
  }

  Handler _buildHandler() {
    final router = Router();
    router.get('/healthz', (Request request) => _json({'ok': true, 'time': nowMs()}));
    router.get('/v1/hub', _handleHubInfo);
    router.get('/v1/time', (Request request) => _json({'serverTimeMs': nowMs()}));
    router.post('/v1/teachers/register', _handleRegisterTeacher);
    router.post('/v1/teachers/login', _handleLoginTeacher);
    router.get('/v1/bootstrap', _handleBootstrap);
    router.post('/v1/teacher/classes', _handleUpdateClasses);
    router.post('/v1/classrooms/register', _handleRegisterClassroom);
    router.get('/v1/streams/<streamId>/messages', _handleMessages);
    router.post('/v1/messages', _handleSendMessage);
    router.post('/v1/ack', _handleAck);
    router.post('/v1/files', _handleRegisterFile);
    router.put('/v1/files/<fileId>/content', _handleUploadFileContent);
    router.get('/v1/files/<fileId>', _handleDownloadFile);
    router.get('/v1/admin/snapshot', _handleAdminSnapshot);
    router.post('/v1/admin/reset-pin', _handleAdminResetPin);
    router.post('/v1/admin/remove-classroom', _handleAdminRemoveClassroom);
    router.post('/v1/admin/teacher-disabled', _handleAdminTeacherDisabled);
    router.post('/v1/admin/remove-teacher', _handleAdminRemoveTeacher);
    router.post('/v1/admin/registration-code', _handleAdminRegistrationCode);
    router.post('/v1/admin/settings', _handleAdminSettings);
    router.post('/v1/admin/admin-pin', _handleAdminChangePin);

    final apiHandler = Pipeline()
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_errorMiddleware())
        .addHandler(router.call);

    final wsHandler = webSocketHandler(_handleWebSocket);
    _staticHandler = _buildStaticHandler();

    return (Request request) async {
      if (request.url.path == 'v1/ws') {
        return wsHandler(request);
      }
      if (request.url.path.startsWith('v1/') ||
          request.url.path == 'healthz' ||
          request.url.path == '') {
        if (request.url.path == '') {
          return _staticHandler!(request);
        }
        return apiHandler(request);
      }
      return _staticHandler!(request);
    };
  }

  Handler _buildStaticHandler() {
    final root = webRoot;
    if (root != null && Directory(root).existsSync()) {
      final staticHandler = createStaticHandler(root, defaultDocument: 'index.html');
      return (Request request) async {
        final response = await staticHandler(request);
        if (response.statusCode == 404) {
          final index = File('$root${Platform.pathSeparator}index.html');
          if (index.existsSync()) {
            return Response.ok(
              index.openRead(),
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
        }
        return response;
      };
    }
    return (Request request) => Response.ok(
          '<!doctype html><html><head><meta charset="utf-8"><title>校联 Hub</title></head>'
          '<body style="font-family:system-ui;padding:40px">'
          '<h1>校联 Hub 正在运行</h1>'
          '<p>Web 客户端尚未部署。请将 Flutter Web 构建产物放到 Hub 的 web 目录，或使用客户端连接。</p>'
          '<p>端口：$actualPort</p></body></html>',
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
  }

  // -------------------------------------------------------------------------
  // HTTP helpers

  Response _json(Object? value, {int statusCode = 200}) => Response(
        statusCode,
        body: jsonEncode(value),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final body = await request.readAsString();
    if (body.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      return asMap(decoded);
    } on FormatException {
      throw HubException('请求格式错误');
    }
  }

  String _tokenFrom(Request request) {
    final header = request.headers['authorization'] ?? '';
    if (header.toLowerCase().startsWith('bearer ')) {
      return header.substring(7).trim();
    }
    return request.url.queryParameters['token'] ?? '';
  }

  Future<SessionSubject> _requireSession(Request request) async {
    final subject = await store.resolveToken(_tokenFrom(request));
    if (subject == null) throw HubException('登录已失效，请重新登录', statusCode: 401);
    return subject;
  }

  Future<void> _requireAdmin(Request request) async {
    final pin = request.headers['x-admin-pin'] ?? request.url.queryParameters['adminPin'] ?? '';
    if (!await store.verifyAdminPin(pin)) {
      throw HubException('管理员 PIN 不正确', statusCode: 401);
    }
  }

  Middleware _corsMiddleware() {
    const headers = {
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET, POST, PUT, OPTIONS',
      'access-control-allow-headers': 'authorization, content-type, x-admin-pin',
      'access-control-max-age': '86400',
    };
    return (inner) => (request) async {
          if (request.method == 'OPTIONS') {
            return Response.ok('', headers: headers);
          }
          final response = await inner(request);
          return response.change(headers: headers);
        };
  }

  Middleware _errorMiddleware() {
    return (inner) => (request) async {
          try {
            return await inner(request);
          } on HubException catch (error) {
            return _json({'error': error.message}, statusCode: error.statusCode);
          } catch (error, stack) {
            _log.severe('request failed ${request.method} /${request.url.path}', error, stack);
            return _json({'error': '服务器内部错误'}, statusCode: 500);
          }
        };
  }

  bool _rateLimited(String name) {
    final now = nowMs();
    final list = _loginFailures[name];
    if (list == null) return false;
    list.removeWhere((t) => now - t > const Duration(minutes: 10).inMilliseconds);
    return list.length >= 5;
  }

  void _recordFailure(String name) {
    final now = nowMs();
    final list = _loginFailures.putIfAbsent(name, () => <int>[]);
    list.add(now);
  }

  void _clearFailures(String name) => _loginFailures.remove(name);

  // -------------------------------------------------------------------------
  // Auth / roster

  Future<Response> _handleHubInfo(Request request) async {
    return _json({
      'id': store.config.id,
      'name': store.config.name,
      'version': appVersion,
      'serverTimeMs': nowMs(),
      'registrationCodeRequired': store.config.registrationRequired,
    });
  }

  Future<Response> _handleRegisterTeacher(Request request) async {
    final body = await _readJson(request);
    final name = normalizeTeacherName(asString(body['name']));
    if (_rateLimited('register:$name')) {
      throw HubException('尝试过于频繁，请稍后再试', statusCode: 429);
    }
    try {
      final result = await store.registerTeacher(
        name: name,
        pin: asString(body['pin']),
        registrationCode: asString(body['registrationCode']),
        classIds: asStringList(body['classIds']),
      );
      _clearFailures('register:$name');
      _broadcastRoster();
      return _json({...result.toJson(), 'serverTimeMs': nowMs()});
    } on HubException {
      _recordFailure('register:$name');
      rethrow;
    }
  }

  Future<Response> _handleLoginTeacher(Request request) async {
    final body = await _readJson(request);
    final name = normalizeTeacherName(asString(body['name']));
    final key = 'login:$name';
    if (_rateLimited(key)) {
      throw HubException('登录失败次数过多，请 10 分钟后再试', statusCode: 429);
    }
    try {
      final result = await store.loginTeacher(
        name: name,
        pin: asString(body['pin']),
      );
      _clearFailures(key);
      _broadcastRoster();
      return _json({...result.toJson(), 'serverTimeMs': nowMs()});
    } on HubException {
      _recordFailure(key);
      rethrow;
    }
  }

  Future<Response> _handleBootstrap(Request request) async {
    final subject = await _requireSession(request);
    final teacher = subject.isTeacher ? await store.teacherById(subject.subjectId) : null;
    final classroom =
        subject.isClassroom ? await store.classroomById(subject.subjectId) : null;
    if (subject.isTeacher && teacher == null) {
      throw HubException('教师账号不存在', statusCode: 401);
    }
    if (subject.isClassroom && classroom == null) {
      throw HubException('教室端绑定不存在', statusCode: 401);
    }
    final classIds = subject.isTeacher
        ? (teacher?.classIds ?? const <String>[])
        : <String>[subject.classId];
    final streams = subject.isTeacher
        ? await store.streamsForTeacher(subject.subjectId)
        : await store.streamsForClass(subject.classId);
    final teachers = subject.isClassroom
        ? await store.teachersForClass(subject.classId)
        : const <TeacherInfo>[];
    final classrooms = <ClassroomInfo>[];
    for (final classId in classIds) {
      classrooms.addAll(await store.classroomsForClass(classId));
    }
    final meshKeys = await store.meshKeysForClasses(classIds);
    final bootstrap = Bootstrap(
      hub: HubInfo(
        id: store.config.id,
        name: store.config.name,
        version: appVersion,
        serverTimeMs: nowMs(),
        registrationCodeRequired: store.config.registrationRequired,
      ),
      serverTimeMs: nowMs(),
      classes: allClasses,
      teacher: teacher,
      classroom: classroom,
      teachers: teachers,
      classrooms: classrooms,
      streams: streams,
      meshKeys: meshKeys,
    );
    return _json(bootstrap.toJson());
  }

  Future<Response> _handleRegisterClassroom(Request request) async {
    final body = await _readJson(request);
    final classroom = await store.registerClassroom(
      installId: asString(body['installId']),
      classId: asString(body['classId']),
      machineName: asString(body['machineName']),
    );
    final auth = await store.authClassroom(classroom);
    _broadcastRoster();
    return _json({...auth.toJson(), 'serverTimeMs': nowMs()});
  }

  Future<Response> _handleUpdateClasses(Request request) async {
    final subject = await _requireSession(request);
    if (!subject.isTeacher) throw HubException('仅教师可以修改任教班级', statusCode: 403);
    final body = await _readJson(request);
    final teacher = await store.updateTeacherClasses(
      subject.subjectId,
      asStringList(body['classIds']),
    );
    final meshKeys = await store.meshKeysForClasses(teacher.classIds);
    final streams = await store.streamsForTeacher(teacher.id);
    _broadcastRoster();
    return _json({
      'teacher': teacher.toJson(),
      'meshKeys': meshKeys,
      'streams': streams.map((e) => e.toJson()).toList(),
      'serverTimeMs': nowMs(),
    });
  }

  // -------------------------------------------------------------------------
  // Messages

  Future<Response> _handleMessages(Request request) async {
    final subject = await _requireSession(request);
    final streamId = Uri.decodeComponent(request.params['streamId'] ?? '');
    final stream = await store.streamById(streamId);
    if (stream == null) throw HubException('会话不存在', statusCode: 404);
    if (subject.isTeacher && stream.teacherId != subject.subjectId) {
      throw HubException('没有该会话的读取权限', statusCode: 403);
    }
    if (subject.isClassroom && stream.classId != subject.classId) {
      throw HubException('没有该会话的读取权限', statusCode: 403);
    }
    final after = int.tryParse(request.url.queryParameters['after'] ?? '0') ?? 0;
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '500') ?? 500;
    final messages = await store.messagesForStream(
      streamId,
      afterSeq: after,
      limit: limit.clamp(1, 2000),
    );
    return _json({
      'messages': messages.map((e) => e.toJson()).toList(),
      'serverTimeMs': nowMs(),
    });
  }

  Future<Response> _handleSendMessage(Request request) async {
    final subject = await _requireSession(request);
    final body = await _readJson(request);
    final message = Message.fromJson(body);
    if (message.id.isEmpty) throw HubException('缺少消息 ID');
    if (message.streamId.isEmpty) throw HubException('缺少会话 ID');
    final saved = await store.appendMessage(message, subject);
    await _broadcastMessage(saved);
    return _json({'message': saved.toJson(), 'serverTimeMs': nowMs()});
  }

  Future<Response> _handleAck(Request request) async {
    final subject = await _requireSession(request);
    final body = await _readJson(request);
    final messageId = asString(body['messageId']);
    if (messageId.isEmpty) throw HubException('缺少消息 ID');
    final message = await store.messageById(messageId);
    if (message == null) throw HubException('消息不存在', statusCode: 404);
    final recipientId = subject.isTeacher
        ? 'teacher:${subject.subjectId}'
        : 'classroom:${subject.subjectId}';
    await store.ackMessage(messageId, recipientId);
    await _notifyDelivery(
      DeliveryInfo(
        messageId: messageId,
        recipientId: recipientId,
        state: 'delivered',
        at: nowMs(),
      ),
    );
    return _json({'ok': true, 'serverTimeMs': nowMs()});
  }

  // -------------------------------------------------------------------------
  // Files

  Future<Response> _handleRegisterFile(Request request) async {
    final subject = await _requireSession(request);
    if (!subject.isTeacher) throw HubException('只有教师可以上传文件', statusCode: 403);
    final body = await _readJson(request);
    final file = await store.registerFile(
      name: asString(body['name']),
      size: asInt(body['size']),
      sha256: asString(body['sha256']),
      mime: asString(body['mime'], 'application/octet-stream'),
    );
    final blob = store.files.fileFor(file.id);
    return _json({
      'file': file.toJson(),
      'uploadRequired': blob == null,
      'serverTimeMs': nowMs(),
    });
  }

  Future<Response> _handleUploadFileContent(Request request) async {
    final subject = await _requireSession(request);
    if (!subject.isTeacher) throw HubException('只有教师可以上传文件', statusCode: 403);
    final fileId = request.params['fileId'] ?? '';
    if (fileId.isEmpty) throw HubException('缺少文件 ID');
    final file = await store.writeFileContent(fileId, request.read());
    return _json({'file': file.toJson(), 'serverTimeMs': nowMs()});
  }

  Future<Response> _handleDownloadFile(Request request) async {
    await _requireSession(request);
    final fileId = request.params['fileId'] ?? '';
    final file = await store.fileById(fileId);
    if (file == null) throw HubException('文件不存在', statusCode: 404);
    if (file.expired) throw HubException('文件已过期', statusCode: 410);
    final blob = store.files.fileFor(fileId);
    if (blob == null) throw HubException('文件内容不存在', statusCode: 404);
    final encoded = Uri.encodeComponent(file.name);
    return Response.ok(
      blob.openRead(),
      headers: {
        'content-type': file.mime,
        'content-length': '${await blob.length()}',
        'content-disposition': "attachment; filename=\"file\"; filename*=UTF-8''$encoded",
      },
    );
  }

  // -------------------------------------------------------------------------
  // Admin

  Future<Response> _handleAdminSnapshot(Request request) async {
    await _requireAdmin(request);
    final online = _connections
        .where((c) => c.subject != null)
        .map(_presenceFromConnection)
        .toList();
    final snapshot = await store.adminSnapshot(onlineDevices: online);
    return _json(snapshot.toJson());
  }

  Future<Response> _handleAdminResetPin(Request request) async {
    await _requireAdmin(request);
    final body = await _readJson(request);
    await store.resetTeacherPin(asString(body['teacherId']), asString(body['pin']));
    return _json({'ok': true});
  }

  Future<Response> _handleAdminRemoveClassroom(Request request) async {
    await _requireAdmin(request);
    final body = await _readJson(request);
    await store.removeClassroom(asString(body['classroomId']));
    _broadcastRoster();
    return _json({'ok': true});
  }

  Future<Response> _handleAdminTeacherDisabled(Request request) async {
    await _requireAdmin(request);
    final body = await _readJson(request);
    await store.setTeacherDisabled(
      asString(body['teacherId']),
      asBool(body['disabled'], true),
    );
    _broadcastRoster();
    return _json({'ok': true});
  }

  Future<Response> _handleAdminRemoveTeacher(Request request) async {
    await _requireAdmin(request);
    final body = await _readJson(request);
    await store.removeTeacher(asString(body['teacherId']));
    _broadcastRoster();
    return _json({'ok': true});
  }

  Future<Response> _handleAdminRegistrationCode(Request request) async {
    await _requireAdmin(request);
    final body = await _readJson(request);
    final code = asString(body['code']);
    if (code.length > 32) throw HubException('注册码过长');
    await store.setRegistrationCode(code, required: asBool(body['required'], true));
    return _json({'ok': true, 'registrationCode': code});
  }

  Future<Response> _handleAdminSettings(Request request) async {
    await _requireAdmin(request);
    final body = await _readJson(request);
    await store.updateSettings(
      name: body['name'] == null ? null : asString(body['name']),
      maxFileBytes: body['maxFileBytes'] == null ? null : asInt(body['maxFileBytes']),
      retentionDays: body['retentionDays'] == null ? null : asInt(body['retentionDays']),
    );
    return _json({'ok': true});
  }

  Future<Response> _handleAdminChangePin(Request request) async {
    await _requireAdmin(request);
    final body = await _readJson(request);
    await store.changeAdminPin(asString(body['pin']));
    return _json({'ok': true});
  }

  // -------------------------------------------------------------------------
  // WebSocket

  void _handleWebSocket(WebSocketChannel channel, String? protocol) {
    final connection = HubConnection(channel);
    connection.authTimer = Timer(const Duration(seconds: 10), () {
      if (connection.subject == null) {
        try {
          channel.sink.close(4001, 'authentication timeout');
        } catch (_) {}
      }
    });
    channel.stream.listen(
      (dynamic raw) => _handleWsMessage(connection, raw),
      onError: (Object error) => _cleanupConnection(connection),
      onDone: () => _cleanupConnection(connection),
      cancelOnError: true,
    );
  }

  Future<void> _handleWsMessage(HubConnection connection, dynamic raw) async {
    if (raw is! String) return;
    Map<String, dynamic> data;
    try {
      data = asMap(jsonDecode(raw));
    } catch (_) {
      return;
    }
    final event = asString(data['event']);
    if (event == 'auth') {
      if (connection.subject != null) return;
      final subject = await store.resolveToken(asString(data['token']));
      if (subject == null) {
        _send(connection, 'error', {'message': '登录已失效'});
        try {
          await connection.channel.sink.close(4001, 'invalid token');
        } catch (_) {}
        return;
      }
      connection.subject = subject;
      connection.deviceId = asString(data['deviceId'], 'device-${newId()}');
      connection.authTimer?.cancel();
      _connections.add(connection);
      _send(connection, 'hello', {
        'serverTimeMs': nowMs(),
        'hubId': store.config.id,
        'hubName': store.config.name,
        'deviceId': connection.deviceId,
      });
      _broadcastPresence();
      _broadcastRoster();
      return;
    }
    if (connection.subject == null) return;
    if (event == 'ack') {
      final messageId = asString(data['messageId']);
      if (messageId.isEmpty) return;
      final subject = connection.subject!;
      final recipientId = subject.isTeacher
          ? 'teacher:${subject.subjectId}'
          : 'classroom:${subject.subjectId}';
      await store.ackMessage(messageId, recipientId);
      await _notifyDelivery(
        DeliveryInfo(
          messageId: messageId,
          recipientId: recipientId,
          state: 'delivered',
          at: nowMs(),
        ),
      );
    } else if (event == 'ping') {
      _send(connection, 'pong', {'serverTimeMs': nowMs()});
    }
  }

  void _cleanupConnection(HubConnection connection) {
    if (connection.closed) return;
    connection.closed = true;
    connection.authTimer?.cancel();
    _connections.remove(connection);
    _broadcastPresence();
  }

  void _send(HubConnection connection, String event, Map<String, dynamic> data) {
    if (connection.closed) return;
    try {
      connection.channel.sink.add(jsonEncode({'event': event, ...data}));
    } catch (_) {
      _cleanupConnection(connection);
    }
  }

  bool _isRelevant(HubConnection connection, Message message) {
    final subject = connection.subject;
    if (subject == null) return false;
    if (subject.isTeacher) return subject.subjectId == message.teacherId;
    if (subject.isClassroom) return subject.classId == message.classId;
    return false;
  }

  Future<void> _broadcastMessage(Message message) async {
    for (final connection in _connections.toList()) {
      if (!_isRelevant(connection, message)) continue;
      _send(connection, 'message', {
        'message': message.toJson(),
        'serverTimeMs': nowMs(),
      });
    }
  }

  Future<void> _notifyDelivery(DeliveryInfo delivery) async {
    final message = await store.messageById(delivery.messageId);
    if (message == null) return;
    for (final connection in _connections.toList()) {
      final subject = connection.subject;
      if (subject == null) continue;
      if (subject.isTeacher && subject.subjectId == message.teacherId) {
        _send(connection, 'delivery', {
          'delivery': delivery.toJson(),
          'serverTimeMs': nowMs(),
        });
      }
    }
  }

  PresenceInfo _presenceFromConnection(HubConnection connection) {
    final subject = connection.subject!;
    return PresenceInfo(
      deviceId: connection.deviceId,
      role: subject.role,
      classId: subject.classId,
      teacherId: subject.isTeacher ? subject.subjectId : '',
      online: true,
      machineName: subject.name,
    );
  }

  void _broadcastPresence() {
    final devices = _connections
        .where((c) => c.subject != null)
        .map(_presenceFromConnection)
        .map((e) => e.toJson())
        .toList();
    for (final connection in _connections.toList()) {
      _send(connection, 'presence', {
        'devices': devices,
        'serverTimeMs': nowMs(),
      });
    }
  }

  void _broadcastRoster() {
    for (final connection in _connections.toList()) {
      _send(connection, 'roster', {'serverTimeMs': nowMs()});
    }
  }

  // -------------------------------------------------------------------------
  // LAN discovery

  Future<void> _startDiscovery() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        hubUdpPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      _discoverySocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        try {
          final data = asMap(jsonDecode(utf8.decode(datagram.data)));
          if (asString(data['svc']) != 'schoollink' ||
              asString(data['type']) != 'discover') {
            return;
          }
          final reply = utf8.encode(jsonEncode({
            'svc': 'schoollink',
            'type': 'hub',
            'hubId': store.config.id,
            'name': store.config.name,
            'version': appVersion,
            'port': actualPort,
          }));
          socket.send(reply, datagram.address, datagram.port);
        } catch (_) {}
      });
      _log.info('Discovery listening on UDP $hubUdpPort');
    } catch (error) {
      _log.warning('Discovery disabled: $error');
    }
  }
}
