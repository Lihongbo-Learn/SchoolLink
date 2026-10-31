import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:school_link_hub/hub.dart';
import 'package:school_link_protocol/protocol.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  test('hub end-to-end: auth, chat, notice, dedupe, files, admin', () async {
    final temp = await Directory.systemTemp.createTemp('schoollink_hub_test_');
    final store = await HubStore.open(dataDir: temp.path);
    final server = HubServer(
      store: store,
      port: 0,
      enableDiscovery: false,
      enableFirewall: false,
    );
    await server.start();
    final base = Uri.parse('http://127.0.0.1:${server.actualPort}');
    final client = http.Client();
    IOWebSocketChannel? socket;

    addTearDown(() async {
      await socket?.sink.close();
      client.close();
      await server.stop();
      await store.close();
      await temp.delete(recursive: true);
    });

    Future<Map<String, dynamic>> post(
      String path,
      Map<String, dynamic> body, {
      String? token,
      Map<String, String>? headers,
    }) async {
      final response = await client.post(
        base.resolve(path),
        headers: {
          'content-type': 'application/json',
          if (token != null) 'authorization': 'Bearer $token',
          ...?headers,
        },
        body: jsonEncode(body),
      );
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        fail('POST $path failed ${response.statusCode}: $decoded');
      }
      return decoded;
    }

    final teacherAuth = await post('/v1/teachers/register', {
      'name': '张老师',
      'pin': '1234',
      'registrationCode': 'SCHOOL26',
      'classIds': ['g1-09'],
    });
    final teacherToken = teacherAuth['token'] as String;
    final teacher = asMap(teacherAuth['teacher']);
    expect(teacher['name'], '张老师');

    final classroomAuth = await post('/v1/classrooms/register', {
      'installId': 'classroom-test-1',
      'classId': 'g1-09',
      'machineName': '高一9班大屏',
    });
    final classroomToken = classroomAuth['token'] as String;
    final classroom = asMap(classroomAuth['classroom']);
    expect(classroom['classId'], 'g1-09');

    final teacherBootstrapResponse = await client.get(
      base.resolve('/v1/bootstrap'),
      headers: {'authorization': 'Bearer $teacherToken'},
    );
    final teacherBootstrap =
        Bootstrap.fromJson(jsonDecode(teacherBootstrapResponse.body) as Map<String, dynamic>);
    expect(teacherBootstrap.streams, hasLength(1));
    final stream = teacherBootstrap.streams.first;
    expect(stream.teacherId, teacher['id']);

    socket = IOWebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${server.actualPort}/v1/ws'),
    );
    final events = socket.stream
        .map((dynamic raw) => asMap(jsonDecode(raw as String)))
        .asBroadcastStream();
    final hello = events.firstWhere((event) => event['event'] == 'hello');
    socket.sink.add(jsonEncode({
      'event': 'auth',
      'token': classroomToken,
      'deviceId': 'classroom-device',
    }));
    await hello.timeout(const Duration(seconds: 5));

    final chat = Message(
      id: newId(),
      streamId: stream.id,
      classId: stream.classId,
      teacherId: stream.teacherId,
      senderType: senderTeacher,
      senderId: 'ignored',
      senderName: 'ignored',
      kind: kindChat,
      text: '同学们好',
      createdAt: nowMs(),
    );
    final chatEvent = events.firstWhere(
      (event) =>
          event['event'] == 'message' &&
          asMap(event['message'])['id'] == chat.id,
    );
    final sentChat = await post('/v1/messages', chat.toJson(), token: teacherToken);
    final chatMessage = Message.fromJson(asMap(sentChat['message']));
    expect(chatMessage.senderName, '张老师');
    expect(chatMessage.seq, isNotNull);
    final receivedChat = await chatEvent.timeout(const Duration(seconds: 5));
    expect(asMap(receivedChat['message'])['text'], '同学们好');

    final duplicate =
        await post('/v1/messages', chat.toJson(), token: teacherToken);
    expect(Message.fromJson(asMap(duplicate['message'])).seq, chatMessage.seq);

    final notice = Message(
      id: newId(),
      streamId: stream.id,
      classId: stream.classId,
      teacherId: stream.teacherId,
      senderType: senderTeacher,
      senderId: 'ignored',
      senderName: 'ignored',
      kind: kindNotice,
      title: '明天带课本',
      text: '请明天带数学课本。',
      closeMode: closeModeAuto,
      autoCloseSec: 20,
      sound: false,
      createdAt: nowMs(),
    );
    await post('/v1/messages', notice.toJson(), token: teacherToken);

    final messagesResponse = await client.get(
      base.resolve('/v1/streams/${Uri.encodeComponent(stream.id)}/messages'),
      headers: {'authorization': 'Bearer $classroomToken'},
    );
    expect(messagesResponse.statusCode, 200, reason: messagesResponse.body);
    final messages = asMapList(
      (jsonDecode(messagesResponse.body) as Map<String, dynamic>)['messages'],
    ).map(Message.fromJson).toList();
    expect(messages.where((m) => m.id == chat.id), hasLength(1));
    final storedNotice = messages.firstWhere((m) => m.id == notice.id);
    expect(storedNotice.closeMode, closeModeAuto);
    expect(storedNotice.autoCloseSec, 20);

    final reply = Message(
      id: newId(),
      streamId: stream.id,
      classId: stream.classId,
      teacherId: stream.teacherId,
      senderType: senderClassroom,
      senderId: 'ignored',
      senderName: 'ignored',
      kind: kindChat,
      text: '收到',
      createdAt: nowMs(),
    );
    final acked = await post('/v1/ack', {'messageId': chat.id}, token: classroomToken);
    expect(acked['ok'], true);
    final sentReply = await post('/v1/messages', reply.toJson(), token: classroomToken);
    expect(Message.fromJson(asMap(sentReply['message'])).senderName, '教室端');

    final fileBytes = utf8.encode('hello school link file');
    final fileMeta = await post('/v1/files', {
      'name': '讲义.txt',
      'size': fileBytes.length,
      'sha256': sha256Hex(fileBytes),
      'mime': 'text/plain',
    }, token: teacherToken);
    final fileInfo = FileInfo.fromJson(asMap(fileMeta['file']));
    final upload = await client.put(
      base.resolve('/v1/files/${fileInfo.id}/content'),
      headers: {'authorization': 'Bearer $teacherToken'},
      body: fileBytes,
    );
    expect(upload.statusCode, 200);
    final download = await client.get(
      base.resolve('/v1/files/${fileInfo.id}'),
      headers: {'authorization': 'Bearer $classroomToken'},
    );
    expect(download.statusCode, 200);
    expect(download.bodyBytes, fileBytes);

    final admin = await client.get(
      base.resolve('/v1/admin/snapshot'),
      headers: {'x-admin-pin': '246810'},
    );
    expect(admin.statusCode, 200);
    final snapshot = AdminSnapshot.fromJson(jsonDecode(admin.body) as Map<String, dynamic>);
    expect(snapshot.teachers.single.name, '张老师');
    expect(snapshot.fileCount, 1);
    expect(snapshot.fileBytes, fileBytes.length);

    final hubInfo = await client.get(base.resolve('/v1/hub'));
    expect(hubInfo.statusCode, 200);
    expect(asMap(jsonDecode(hubInfo.body))['registrationCodeRequired'], true);
  });
}
