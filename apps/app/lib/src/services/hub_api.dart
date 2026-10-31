import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:school_link_protocol/protocol.dart';

class HubApiException implements Exception {
  HubApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class FileUploadTicket {
  const FileUploadTicket({required this.file, required this.uploadRequired});

  final FileInfo file;
  final bool uploadRequired;
}

class ClassesUpdate {
  const ClassesUpdate({
    required this.teacher,
    required this.meshKeys,
    required this.streams,
  });

  final TeacherInfo teacher;
  final Map<String, String> meshKeys;
  final List<StreamInfo> streams;
}

class HubApi {
  HubApi({required String baseUrl, this.token}) : baseUrl = normalizeBaseUrl(baseUrl);

  final String baseUrl;
  String? token;
  final http.Client _client = http.Client();

  static String normalizeBaseUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return value;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _authHeaders => {
        if (token != null && token!.isNotEmpty) 'authorization': 'Bearer $token',
        'content-type': 'application/json',
      };

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final request = http.Request(method, _uri(path));
    if (auth) {
      request.headers.addAll(_authHeaders);
    } else {
      request.headers['content-type'] = 'application/json';
    }
    if (body != null) request.body = jsonEncode(body);
    try {
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 400) {
        String message = '服务器错误 (${response.statusCode})';
        try {
          final json = asMap(jsonDecode(response.body));
          if (asString(json['error']).isNotEmpty) message = asString(json['error']);
        } catch (_) {}
        throw HubApiException(message, statusCode: response.statusCode);
      }
      if (response.body.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return asMap(decoded);
    } on HubApiException {
      rethrow;
    } on TimeoutException {
      throw HubApiException('连接服务器超时');
    } catch (error) {
      throw HubApiException('无法连接服务器：$error');
    }
  }

  Future<HubInfo> hubInfo() async {
    final json = await _sendJson('GET', '/v1/hub', auth: false);
    return HubInfo.fromJson(json);
  }

  Future<AuthResult> registerTeacher({
    required String name,
    required String pin,
    required String registrationCode,
    required List<String> classIds,
  }) async {
    final json = await _sendJson('POST', '/v1/teachers/register', auth: false, body: {
      'name': name,
      'pin': pin,
      'registrationCode': registrationCode,
      'classIds': classIds,
    });
    final auth = AuthResult.fromJson(json);
    token = auth.token;
    return auth;
  }

  Future<AuthResult> loginTeacher({required String name, required String pin}) async {
    final json = await _sendJson('POST', '/v1/teachers/login', auth: false, body: {
      'name': name,
      'pin': pin,
    });
    final auth = AuthResult.fromJson(json);
    token = auth.token;
    return auth;
  }

  Future<AuthResult> registerClassroom({
    required String installId,
    required String classId,
    required String machineName,
  }) async {
    final json = await _sendJson('POST', '/v1/classrooms/register', auth: false, body: {
      'installId': installId,
      'classId': classId,
      'machineName': machineName,
    });
    final auth = AuthResult.fromJson(json);
    token = auth.token;
    return auth;
  }

  Future<Bootstrap> bootstrap() async {
    final json = await _sendJson('GET', '/v1/bootstrap');
    return Bootstrap.fromJson(json);
  }

  Future<ClassesUpdate> updateClasses(List<String> classIds) async {
    final json = await _sendJson('POST', '/v1/teacher/classes', body: {
      'classIds': classIds,
    });
    return ClassesUpdate(
      teacher: TeacherInfo.fromJson(asMap(json['teacher'])),
      meshKeys: asStringMap(json['meshKeys']),
      streams: asMapList(json['streams']).map(StreamInfo.fromJson).toList(),
    );
  }

  Future<List<Message>> messagesForStream(String streamId, {int after = 0}) async {
    final encoded = Uri.encodeComponent(streamId);
    final json = await _sendJson(
      'GET',
      '/v1/streams/$encoded/messages?after=$after&limit=1000',
      timeout: const Duration(seconds: 25),
    );
    return asMapList(json['messages']).map(Message.fromJson).toList();
  }

  Future<Message> sendMessage(Message message) async {
    final json = await _sendJson('POST', '/v1/messages', body: message.toJson());
    return Message.fromJson(asMap(json['message']));
  }

  Future<void> ack(String messageId) async {
    await _sendJson('POST', '/v1/ack', body: {'messageId': messageId});
  }

  Future<FileUploadTicket> registerFile({
    required String name,
    required int size,
    required String sha256,
    required String mime,
  }) async {
    final json = await _sendJson('POST', '/v1/files', body: {
      'name': name,
      'size': size,
      'sha256': sha256,
      'mime': mime,
    });
    return FileUploadTicket(
      file: FileInfo.fromJson(asMap(json['file'])),
      uploadRequired: asBool(json['uploadRequired'], true),
    );
  }

  Future<FileInfo> uploadFileBytes(String fileId, List<int> bytes) async {
    final request = http.Request('PUT', _uri('/v1/files/$fileId/content'));
    request.headers['authorization'] = 'Bearer ${token ?? ''}';
    request.headers['content-type'] = 'application/octet-stream';
    request.bodyBytes = Uint8List.fromList(bytes);
    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(minutes: 10));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 400) {
        String message = '文件上传失败 (${response.statusCode})';
        try {
          final json = asMap(jsonDecode(response.body));
          if (asString(json['error']).isNotEmpty) message = asString(json['error']);
        } catch (_) {}
        throw HubApiException(message, statusCode: response.statusCode);
      }
      final json = asMap(jsonDecode(response.body));
      return FileInfo.fromJson(asMap(json['file']));
    } on HubApiException {
      rethrow;
    } on TimeoutException {
      throw HubApiException('文件上传超时');
    } catch (error) {
      throw HubApiException('文件上传失败：$error');
    }
  }

  Future<Uint8List> downloadFile(String fileId) async {
    final request = http.Request('GET', _uri('/v1/files/$fileId'));
    request.headers['authorization'] = 'Bearer ${token ?? ''}';
    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(minutes: 10));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 400) {
        String message = '文件下载失败 (${response.statusCode})';
        try {
          final json = asMap(jsonDecode(response.body));
          if (asString(json['error']).isNotEmpty) message = asString(json['error']);
        } catch (_) {}
        throw HubApiException(message, statusCode: response.statusCode);
      }
      return response.bodyBytes;
    } on HubApiException {
      rethrow;
    } on TimeoutException {
      throw HubApiException('文件下载超时');
    } catch (error) {
      throw HubApiException('文件下载失败：$error');
    }
  }

  Map<String, String> _adminHeaders(String pin) => {
        'x-admin-pin': pin,
        'content-type': 'application/json',
      };

  Future<AdminSnapshot> adminSnapshot(String pin) async {
    final request = http.Request('GET', _uri('/v1/admin/snapshot'));
    request.headers.addAll(_adminHeaders(pin));
    final streamed = await _client.send(request).timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 400) {
      String message = '管理员验证失败';
      try {
        final json = asMap(jsonDecode(response.body));
        if (asString(json['error']).isNotEmpty) message = asString(json['error']);
      } catch (_) {}
      throw HubApiException(message, statusCode: response.statusCode);
    }
    return AdminSnapshot.fromJson(
      asMap(jsonDecode(utf8.decode(response.bodyBytes))),
    );
  }

  Future<void> _adminPost(String path, Map<String, dynamic> body, String pin) async {
    final request = http.Request('POST', _uri(path));
    request.headers.addAll(_adminHeaders(pin));
    request.body = jsonEncode(body);
    final streamed = await _client.send(request).timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 400) {
      String message = '管理员操作失败';
      try {
        final json = asMap(jsonDecode(response.body));
        if (asString(json['error']).isNotEmpty) message = asString(json['error']);
      } catch (_) {}
      throw HubApiException(message, statusCode: response.statusCode);
    }
  }

  Future<void> adminResetPin(String pin, String teacherId, String newPin) =>
      _adminPost('/v1/admin/reset-pin', {'teacherId': teacherId, 'pin': newPin}, pin);

  Future<void> adminRemoveClassroom(String pin, String classroomId) =>
      _adminPost('/v1/admin/remove-classroom', {'classroomId': classroomId}, pin);

  Future<void> adminSetTeacherDisabled(String pin, String teacherId, bool disabled) =>
      _adminPost('/v1/admin/teacher-disabled', {
        'teacherId': teacherId,
        'disabled': disabled,
      }, pin);

  Future<void> adminRemoveTeacher(String pin, String teacherId) =>
      _adminPost('/v1/admin/remove-teacher', {'teacherId': teacherId}, pin);

  Future<void> adminSetRegistrationCode(
    String pin,
    String code, {
    bool required = true,
  }) =>
      _adminPost('/v1/admin/registration-code', {
        'code': code,
        'required': required,
      }, pin);

  Future<void> adminUpdateSettings(
    String pin, {
    String? name,
    int? maxFileBytes,
    int? retentionDays,
  }) =>
      _adminPost('/v1/admin/settings', {
        'name': ?name,
        'maxFileBytes': ?maxFileBytes,
        'retentionDays': ?retentionDays,
      }, pin);

  Future<void> adminChangePin(String pin, String newPin) =>
      _adminPost('/v1/admin/admin-pin', {'pin': newPin}, pin);

  void close() => _client.close();
}
