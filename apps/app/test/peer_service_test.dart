import 'package:flutter_test/flutter_test.dart';
import 'package:school_link/src/services/peer_info.dart';
import 'package:school_link/src/services/peer_service.dart';
import 'package:school_link_protocol/protocol.dart';

void main() {
  test('two native peers discover, handshake and deliver an HMAC message', () async {
    const classId = 'g1-09';
    const teacherId = 'teacher-1';
    const meshKey = 'mesh-key-for-test';
    final received = <Message>[];
    final teacherPeers = <PeerInfo>[];
    final classroomPeers = <PeerInfo>[];

    final teacher = PeerService(
      serverPort: 0,
      discoveryPort: 18424,
      onMessage: (message) async {},
      onPresence: (peers) {
        teacherPeers
          ..clear()
          ..addAll(peers);
      },
    );
    final classroom = PeerService(
      serverPort: 0,
      discoveryPort: 18424,
      onMessage: (message) async => received.add(message),
      onPresence: (peers) {
        classroomPeers
          ..clear()
          ..addAll(peers);
      },
    );

    addTearDown(() async {
      await teacher.stop();
      await classroom.stop();
    });

    await teacher.start(const PeerConfig(
      deviceId: 'device-teacher',
      role: senderTeacher,
      name: '张老师',
      classIds: [classId],
      teacherId: teacherId,
      meshKeys: {classId: meshKey},
    ));
    await classroom.start(const PeerConfig(
      deviceId: 'device-classroom',
      role: senderClassroom,
      name: '教室电脑',
      classIds: [classId],
      teacherId: '',
      meshKeys: {classId: meshKey},
    ));

    final deadline = DateTime.now().add(const Duration(seconds: 8));
    var delivered = 0;
    final message = Message(
      id: newId(),
      streamId: streamIdFor(classId, teacherId),
      classId: classId,
      teacherId: teacherId,
      senderType: senderTeacher,
      senderId: teacherId,
      senderName: '张老师',
      kind: kindNotice,
      title: '直连测试',
      text: '这条消息应该通过直连到达教室。',
      createdAt: nowMs(),
    );
    while (DateTime.now().isBefore(deadline)) {
      if (classroomPeers.isNotEmpty && teacherPeers.isNotEmpty) {
        delivered = await teacher.send(message);
        if (delivered > 0 && received.any((m) => m.id == message.id)) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(teacherPeers, isNotEmpty);
    expect(classroomPeers, isNotEmpty);
    expect(delivered, greaterThan(0));
    expect(received.where((m) => m.id == message.id), hasLength(1));
    expect(received.first.kind, kindNotice);
  }, timeout: const Timeout(Duration(seconds: 20)));
}
