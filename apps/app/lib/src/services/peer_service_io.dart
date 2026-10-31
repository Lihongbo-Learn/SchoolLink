import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:school_link_protocol/protocol.dart';

import 'peer_info.dart';

class _PeerConnection {
  _PeerConnection(this.socket, {required this.outgoing, required this.host});

  final WebSocket socket;
  final bool outgoing;
  final String host;
  PeerInfo? peer;
  String? helloClassId;
  String? meshKey;
  bool authenticated = false;
  Timer? authTimer;
  StreamSubscription<dynamic>? subscription;

  String get deviceId => peer?.deviceId ?? '';
}

class PeerService {
  PeerService({
    required this.onMessage,
    required this.onPresence,
    this.serverPort = peerPort,
    this.discoveryPort = peerDiscoveryPort,
  });

  final PeerMessageHandler onMessage;
  final PeerPresenceHandler onPresence;
  final int serverPort;
  final int discoveryPort;

  PeerConfig? _config;
  HttpServer? _server;
  RawDatagramSocket? _discovery;
  Timer? _announceTimer;
  Timer? _expireTimer;
  final List<_PeerConnection> _connections = <_PeerConnection>[];
  final Map<String, PeerInfo> _peers = <String, PeerInfo>{};
  final Set<String> _connecting = <String>{};
  final Map<String, Set<String>> _acks = <String, Set<String>>{};
  final Map<String, Completer<void>> _ackSignals = <String, Completer<void>>{};
  bool _started = false;
  int _actualPort = peerPort;
  String? _error;

  bool get running => _started;

  String? get error => _error;

  List<PeerInfo> get peers => _peers.values.toList(growable: false);

  Future<void> start(PeerConfig config) async {
    await stop();
    _config = config;
    _started = true;
    _error = null;
    if (config.classIds.isEmpty || config.meshKeys.isEmpty) return;
    HttpServer? server;
    if (serverPort == 0) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      } catch (_) {}
    } else {
      for (var attempt = 0; attempt < 12; attempt++) {
        try {
          server = await HttpServer.bind(InternetAddress.anyIPv4, serverPort + attempt);
          break;
        } catch (_) {}
      }
    }
    if (server == null) {
      _error = '无法监听直连端口';
      return;
    }
    _server = server;
    _actualPort = server.port;
    server.listen(_handleHttpRequest, onError: (_) {});
    if (Platform.isAndroid) {
      try {
        await const MethodChannel('cn.schoollink/multicast').invokeMethod('enable');
      } catch (_) {}
    }
    await _startDiscovery();
  }

  Future<void> update(PeerConfig config) async {
    if (!_started) {
      await start(config);
      return;
    }
    _config = config;
    _announce();
  }

  Future<void> stop() async {
    if (Platform.isAndroid) {
      try {
        await const MethodChannel('cn.schoollink/multicast').invokeMethod('disable');
      } catch (_) {}
    }
    _started = false;
    _announceTimer?.cancel();
    _expireTimer?.cancel();
    _announceTimer = null;
    _expireTimer = null;
    _discovery?.close();
    _discovery = null;
    for (final connection in _connections.toList()) {
      await connection.subscription?.cancel();
      connection.authTimer?.cancel();
      try {
        await connection.socket.close(1000, 'peer stopped');
      } catch (_) {}
    }
    _connections.clear();
    _connecting.clear();
    _peers.clear();
    _ackSignals.clear();
    _acks.clear();
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    if (request.uri.path != '/peer' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      final host = request.connectionInfo?.remoteAddress.address ?? '';
      final connection = _PeerConnection(socket, outgoing: false, host: host);
      connection.authTimer = Timer(const Duration(seconds: 8), () {
        if (!connection.authenticated) {
          connection.socket.close(4000, 'handshake timeout');
        }
      });
      connection.subscription = socket.listen(
        (dynamic raw) => _onFrame(connection, raw),
        onError: (_) => _dropConnection(connection),
        onDone: () => _dropConnection(connection),
        cancelOnError: true,
      );
      _connections.add(connection);
    } catch (error) {
      _error = '直连握手失败：$error';
    }
  }

  Future<void> _connect(PeerInfo peer) async {
    final config = _config;
    if (config == null || !_started) return;
    if (_connecting.contains(peer.deviceId) ||
        _connections.any((c) => c.deviceId == peer.deviceId && c.authenticated)) {
      return;
    }
    final classId = _commonClass(peer);
    if (classId == null) return;
    final key = config.meshKeys[classId];
    if (key == null || key.isEmpty) return;
    _connecting.add(peer.deviceId);
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(
        'ws://${peer.host}:${peer.port}/peer',
      ).timeout(const Duration(seconds: 5));
      final connection = _PeerConnection(socket, outgoing: true, host: peer.host);
      connection.peer = peer;
      connection.helloClassId = classId;
      connection.meshKey = key;
      connection.authTimer = Timer(const Duration(seconds: 8), () {
        if (!connection.authenticated) {
          connection.socket.close(4000, 'handshake timeout');
        }
      });
      connection.subscription = socket.listen(
        (dynamic raw) => _onFrame(connection, raw),
        onError: (_) => _dropConnection(connection),
        onDone: () => _dropConnection(connection),
        cancelOnError: true,
      );
      _connections.add(connection);
      _sendHello(connection);
    } catch (_) {
      try {
        await socket?.close();
      } catch (_) {}
    } finally {
      _connecting.remove(peer.deviceId);
    }
  }

  void _sendHello(_PeerConnection connection) {
    final config = _config;
    final classId = connection.helloClassId;
    final key = connection.meshKey;
    if (config == null || classId == null || key == null) return;
    final nonce = randomToken(bytes: 8);
    final ts = nowMs();
    final sig = signPeerHandshake(
      meshKey: key,
      deviceId: config.deviceId,
      role: config.role,
      classId: classId,
      nonce: nonce,
      timestamp: ts,
    );
    _sendRaw(connection, {
      'type': 'hello',
      'deviceId': config.deviceId,
      'role': config.role,
      'classId': classId,
      'classIds': config.classIds,
      'teacherId': config.teacherId,
      'name': config.name,
      'ts': ts,
      'nonce': nonce,
      'sig': sig,
    });
  }

  void _onFrame(_PeerConnection connection, dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> data;
    try {
      data = asMap(jsonDecode(raw));
    } catch (_) {
      return;
    }
    final type = asString(data['type']);
    if (type == 'hello') {
      _handleHello(connection, data);
    } else if (type == 'hello-ok') {
      if (connection.peer != null) {
        connection.authenticated = true;
        connection.authTimer?.cancel();
      }
    } else if (type == 'msg') {
      unawaited(_handleMessage(connection, data));
    } else if (type == 'ack') {
      _handleAck(connection, data);
    }
  }

  void _handleHello(_PeerConnection connection, Map<String, dynamic> data) {
    final config = _config;
    if (config == null || connection.authenticated) return;
    final classId = asString(data['classId']);
    final key = config.meshKeys[classId];
    if (key == null || key.isEmpty) return;
    final role = asString(data['role']);
    if (role == config.role) return;
    final validRole = config.role == senderClassroom
        ? (role == senderTeacher && classId == _firstClass(config.classIds))
        : (role == senderClassroom && config.classIds.contains(classId));
    if (!validRole) return;
    final deviceId = asString(data['deviceId']);
    final nonce = asString(data['nonce']);
    if (deviceId.isEmpty || nonce.isEmpty) return;
    final ok = verifyPeerHandshake(
      meshKey: key,
      deviceId: deviceId,
      role: role,
      classId: classId,
      nonce: nonce,
      timestamp: asInt(data['ts']),
      signature: asString(data['sig']),
    );
    if (!ok) return;
    final known = _peers[deviceId];
    connection.peer = PeerInfo(
      deviceId: deviceId,
      role: role,
      classIds: asStringList(data['classIds']).isEmpty
          ? [classId]
          : asStringList(data['classIds']),
      teacherId: asString(data['teacherId']),
      name: asString(data['name'], '未知设备'),
      host: known?.host ?? connection.host,
      port: known?.port ?? 0,
      lastSeen: nowMs(),
    );
    connection.helloClassId = classId;
    connection.meshKey = key;
    connection.authenticated = true;
    connection.authTimer?.cancel();
    _sendRaw(connection, {'type': 'hello-ok'});
    _notifyPresence();
  }

  Future<void> _handleMessage(
    _PeerConnection connection,
    Map<String, dynamic> data,
  ) async {
    final config = _config;
    if (config == null || !connection.authenticated) return;
    final messageMap = asMap(data['message']);
    if (messageMap.isEmpty) return;
    final classId = asString(messageMap['classId']);
    final key = config.meshKeys[classId];
    if (key == null) return;
    final message = decodePeerEnvelope(data, key);
    if (message == null) return;
    if (config.role == senderClassroom) {
      if (!message.fromTeacher || message.classId != _firstClass(config.classIds)) {
        return;
      }
    } else {
      if (!message.fromClassroom ||
          message.teacherId != config.teacherId ||
          !config.classIds.contains(message.classId)) {
        return;
      }
    }
    try {
      await onMessage(message);
    } catch (_) {}
    _sendRaw(connection, {'type': 'ack', 'id': message.id});
  }

  void _handleAck(_PeerConnection connection, Map<String, dynamic> data) {
    final id = asString(data['id']);
    if (id.isEmpty) return;
    _acks.putIfAbsent(id, () => <String>{}).add(connection.deviceId);
    _ackSignals[id]?.complete();
  }

  Future<int> send(Message message) async {
    final config = _config;
    if (!_started || config == null || message.isFile) return 0;
    final key = config.meshKeys[message.classId];
    if (key == null) return 0;
    final envelope = peerEnvelope(message, key);
    final targets = <String, _PeerConnection>{};
    for (final connection in _connections) {
      final peer = connection.peer;
      if (!connection.authenticated || peer == null) continue;
      if (message.fromTeacher) {
        if (!peer.isClassroom || !peer.classIds.contains(message.classId)) continue;
      } else {
        if (!peer.isTeacher || peer.teacherId != message.teacherId) continue;
      }
      targets.putIfAbsent(peer.deviceId, () => connection);
    }
    if (targets.isEmpty) return 0;
    final signal = Completer<void>();
    _ackSignals[message.id] = signal;
    _acks[message.id] = <String>{};
    for (final connection in targets.values) {
      _sendRaw(connection, {'type': 'msg', ...envelope});
    }
    try {
      await signal.future.timeout(const Duration(milliseconds: 1500));
    } catch (_) {}
    final count = _acks.remove(message.id)?.length ?? 0;
    _ackSignals.remove(message.id);
    return count;
  }

  void _sendRaw(_PeerConnection connection, Map<String, dynamic> data) {
    try {
      connection.socket.add(jsonEncode(data));
    } catch (_) {}
  }

  void _dropConnection(_PeerConnection connection) {
    connection.authTimer?.cancel();
    connection.subscription?.cancel();
    _connections.remove(connection);
    _notifyPresence();
  }

  String? _firstClass(List<String> ids) => ids.isEmpty ? null : ids.first;

  String? _commonClass(PeerInfo peer) {
    final config = _config;
    if (config == null) return null;
    if (config.role == senderClassroom) {
      final own = _firstClass(config.classIds);
      if (own == null) return null;
      return peer.classIds.contains(own) ? own : null;
    }
    for (final id in peer.classIds) {
      if (config.classIds.contains(id)) return id;
    }
    return null;
  }

  bool _relevant(PeerInfo peer) {
    final config = _config;
    if (config == null) return false;
    if (config.role == senderTeacher) {
      return peer.isClassroom &&
          peer.classIds.any((id) => config.classIds.contains(id));
    }
    final own = _firstClass(config.classIds);
    return peer.isTeacher && own != null && peer.classIds.contains(own);
  }

  Future<void> _startDiscovery() async {
    try {
      _discovery = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _discovery!.broadcastEnabled = true;
      _discovery!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _discovery!.receive();
        if (datagram == null) return;
        _handleAnnouncement(datagram);
      });
      _announce();
      _announceTimer = Timer.periodic(const Duration(seconds: 4), (_) => _announce());
      _expireTimer = Timer.periodic(const Duration(seconds: 6), (_) => _expirePeers());
    } catch (error) {
      _error = '直连发现不可用：$error';
    }
  }

  void _announce() {
    final config = _config;
    final socket = _discovery;
    if (config == null || socket == null) return;
    final payload = utf8.encode(jsonEncode({
      'svc': 'schoollink',
      'type': 'peer',
      'deviceId': config.deviceId,
      'role': config.role,
      'classIds': config.classIds,
      'teacherId': config.teacherId,
      'name': config.name,
      'peerPort': _actualPort,
      'ts': nowMs(),
    }));
    try {
      socket.send(payload, InternetAddress('255.255.255.255'), discoveryPort);
      socket.send(payload, InternetAddress.loopbackIPv4, discoveryPort);
    } catch (_) {}
    NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false)
        .then((interfaces) {
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length != 4) continue;
          try {
            socket.send(
              payload,
              InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'),
              discoveryPort,
            );
          } catch (_) {}
        }
      }
    }).catchError((_) {});
  }

  void _handleAnnouncement(Datagram datagram) {
    final config = _config;
    if (config == null) return;
    try {
      final data = asMap(jsonDecode(utf8.decode(datagram.data)));
      if (asString(data['svc']) != 'schoollink' ||
          asString(data['type']) != 'peer') {
        return;
      }
      final deviceId = asString(data['deviceId']);
      if (deviceId.isEmpty || deviceId == config.deviceId) return;
      final role = asString(data['role']);
      if (role == config.role) return;
      final port = asInt(data['peerPort']);
      if (port <= 0) return;
      final peer = PeerInfo(
        deviceId: deviceId,
        role: role,
        classIds: asStringList(data['classIds']),
        teacherId: asString(data['teacherId']),
        name: asString(data['name'], '未知设备'),
        host: datagram.address.address,
        port: port,
        lastSeen: nowMs(),
      );
      if (!_relevant(peer)) return;
      _peers[deviceId] = peer;
      _notifyPresence();
      unawaited(_connect(peer));
    } catch (_) {}
  }

  void _expirePeers() {
    final now = nowMs();
    final before = _peers.length;
    _peers.removeWhere((_, peer) => now - peer.lastSeen > 20000);
    if (_peers.length != before) _notifyPresence();
  }

  void _notifyPresence() {
    final list = _peers.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    onPresence(list);
  }
}
