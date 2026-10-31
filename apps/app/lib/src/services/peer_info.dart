import 'package:school_link_protocol/protocol.dart';

typedef PeerMessageHandler = Future<void> Function(Message message);
typedef PeerPresenceHandler = void Function(List<PeerInfo> peers);

class PeerInfo {
  const PeerInfo({
    required this.deviceId,
    required this.role,
    required this.classIds,
    required this.teacherId,
    required this.name,
    required this.host,
    required this.port,
    required this.lastSeen,
  });

  final String deviceId;
  final String role;
  final List<String> classIds;
  final String teacherId;
  final String name;
  final String host;
  final int port;
  final int lastSeen;

  bool get isTeacher => role == 'teacher';
  bool get isClassroom => role == 'classroom';
}

class PeerConfig {
  const PeerConfig({
    required this.deviceId,
    required this.role,
    required this.name,
    required this.classIds,
    required this.teacherId,
    required this.meshKeys,
  });

  final String deviceId;
  final String role;
  final String name;
  final List<String> classIds;
  final String teacherId;
  final Map<String, String> meshKeys;
}
