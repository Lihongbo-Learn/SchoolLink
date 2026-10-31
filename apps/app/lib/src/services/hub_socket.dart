import 'dart:async';
import 'dart:convert';

import 'package:school_link_protocol/protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class HubSocket {
  HubSocket({
    required this.baseUrl,
    required this.token,
    required this.deviceId,
    required this.onEvent,
    required this.onStatus,
  });

  final String baseUrl;
  final String token;
  final String deviceId;
  final void Function(Map<String, dynamic> event) onEvent;
  final void Function(bool connected, {String? message}) onStatus;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _attempt = 0;
  bool _closed = false;
  bool _connected = false;

  bool get connected => _connected;

  Uri get _uri {
    final base = Uri.parse(baseUrl);
    return Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      userInfo: base.userInfo.isEmpty ? null : base.userInfo,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/v1/ws',
    );
  }

  void connect() {
    if (_closed) return;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    try {
      final channel = WebSocketChannel.connect(_uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        (dynamic raw) {
          if (raw is! String) return;
          try {
            final event = asMap(jsonDecode(raw));
            final eventName = asString(event['event']);
            if (eventName == 'hello') {
              _connected = true;
              _attempt = 0;
              onStatus(true);
              _startPing();
            }
            onEvent(event);
          } catch (_) {}
        },
        onError: (Object error) => _handleClosed('连接错误：$error'),
        onDone: () => _handleClosed('连接已断开'),
        cancelOnError: true,
      );
      channel.ready.then((_) {
        _send({
          'event': 'auth',
          'token': token,
          'deviceId': deviceId,
        });
      }).catchError((Object error) {
        _handleClosed('无法连接实时通道');
      });
    } catch (error) {
      _handleClosed('无法连接实时通道');
    }
  }

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void sendAck(String messageId) {
    _send({'event': 'ack', 'messageId': messageId});
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _send({'event': 'ping'});
    });
  }

  void _handleClosed(String message) {
    if (_closed) return;
    final wasConnected = _connected;
    _connected = false;
    _pingTimer?.cancel();
    if (wasConnected) onStatus(false, message: message);
    if (_reconnectTimer?.isActive ?? false) return;
    _attempt += 1;
    final seconds = (3 * _attempt).clamp(3, 15);
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_closed) connect();
    });
  }

  Future<void> dispose() async {
    _closed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    await _subscription?.cancel();
    try {
      await _channel?.sink.close(1000, 'client closed');
    } catch (_) {}
    _channel = null;
  }
}
