import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sembast/sembast_io.dart';
import 'package:school_link_protocol/protocol.dart';

import 'config.dart';
import 'errors.dart';
import 'file_store.dart';

class SessionSubject {
  const SessionSubject({
    required this.role,
    required this.subjectId,
    required this.name,
    required this.classIds,
    this.classId = '',
  });

  final String role;
  final String subjectId;
  final String name;
  final List<String> classIds;
  final String classId;

  bool get isTeacher => role == senderTeacher;
  bool get isClassroom => role == senderClassroom;
}

class HubStore {
  HubStore._(this.db, this.dataDir, this.config, this.files);

  final Database db;
  final String dataDir;
  final HubConfig config;
  final FileStore files;

  final StoreRef<String, Map<String, Object?>> _teachers =
      StoreRef<String, Map<String, Object?>>('teachers');
  final StoreRef<String, Map<String, Object?>> _classrooms =
      StoreRef<String, Map<String, Object?>>('classrooms');
  final StoreRef<String, Map<String, Object?>> _streams =
      StoreRef<String, Map<String, Object?>>('streams');
  final StoreRef<String, Map<String, Object?>> _messageIndex =
      StoreRef<String, Map<String, Object?>>('message_index');
  final StoreRef<String, Map<String, Object?>> _sessions =
      StoreRef<String, Map<String, Object?>>('sessions');
  final StoreRef<String, Map<String, Object?>> _files =
      StoreRef<String, Map<String, Object?>>('files');
  final StoreRef<String, Map<String, Object?>> _filesBySha =
      StoreRef<String, Map<String, Object?>>('files_by_sha');
  final StoreRef<String, Map<String, Object?>> _acks =
      StoreRef<String, Map<String, Object?>>('acks');
  final StoreRef<String, int> _meta = StoreRef<String, int>('meta');
  final StoreRef<String, String> _meshKeys = StoreRef<String, String>('mesh_keys');

  final int startedAt = nowMs();
  Future<void> _tail = Future<void>.value();

  static Future<HubStore> open({
    required String dataDir,
    HubConfig? config,
    String? name,
  }) async {
    await Directory(dataDir).create(recursive: true);
    final cfg = config ?? await HubConfigFile.loadOrCreate(dataDir, name: name);
    final db = await databaseFactoryIo.openDatabase(p.join(dataDir, 'hub.db'));
    final fileStore = FileStore(dataDir);
    await fileStore.init();
    final store = HubStore._(db, dataDir, cfg, fileStore);
    await store._ensureDefaults();
    return store;
  }

  Future<void> _ensureDefaults() async {
    // Ensures the sequence record exists and prunes expired file blobs.
    await _meta.record('seq').get(db);
    await cleanupExpiredFiles();
  }

  Future<void> close() async {
    await db.close();
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _tail;
    _tail = completer.future;
    return (() async {
      await previous;
      try {
        return await action();
      } finally {
        completer.complete();
      }
    })();
  }

  StoreRef<int, Map<String, Object?>> _messagesOf(String streamId) {
    final encoded = base64UrlEncode(utf8.encode(streamId)).replaceAll('=', '');
    return StoreRef<int, Map<String, Object?>>('messages_$encoded');
  }

  Future<void> _saveConfig() => HubConfigFile.save(dataDir, config);

  // -------------------------------------------------------------------------
  // Classes / sessions

  List<String> validateClassIds(Iterable<String> input) {
    final result = <String>[];
    for (final id in input) {
      if (parseClassId(id) == null) {
        throw HubException('无效的班级：$id');
      }
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }

  Future<String> meshKeyForClass(String classId) async {
    var key = await _meshKeys.record(classId).get(db);
    if (key == null || key.isEmpty) {
      key = randomToken(bytes: 24);
      await _meshKeys.record(classId).put(db, key);
    }
    return key;
  }

  Future<Map<String, String>> meshKeysForClasses(Iterable<String> classIds) async {
    final result = <String, String>{};
    for (final id in classIds) {
      result[id] = await meshKeyForClass(id);
    }
    return result;
  }

  Future<AuthResult> _authForTeacher(TeacherInfo teacher) async {
    final token = randomToken();
    final hash = sha256OfString(token);
    await _sessions.record(hash).put(db, {
      'role': senderTeacher,
      'subjectId': teacher.id,
      'name': teacher.name,
      'classIds': teacher.classIds,
      'classId': '',
      'createdAt': nowMs(),
      'expiresAt': nowMs() + const Duration(days: 365).inMilliseconds,
    });
    return AuthResult(
      token: token,
      role: senderTeacher,
      classIds: teacher.classIds,
      teacher: teacher,
      meshKeys: await meshKeysForClasses(teacher.classIds),
    );
  }

  Future<AuthResult> _authForClassroom(ClassroomInfo classroom) async {
    final token = randomToken();
    final hash = sha256OfString(token);
    await _sessions.record(hash).put(db, {
      'role': senderClassroom,
      'subjectId': classroom.id,
      'name': classroom.machineName,
      'classIds': [classroom.classId],
      'classId': classroom.classId,
      'createdAt': nowMs(),
      'expiresAt': nowMs() + const Duration(days: 365).inMilliseconds,
    });
    return AuthResult(
      token: token,
      role: senderClassroom,
      classIds: [classroom.classId],
      classroom: classroom,
      meshKeys: await meshKeysForClasses([classroom.classId]),
    );
  }

  Future<SessionSubject?> resolveToken(String token) async {
    if (token.isEmpty) return null;
    final hash = sha256OfString(token);
    final record = await _sessions.record(hash).get(db);
    if (record == null) return null;
    if (asInt(record['expiresAt']) < nowMs()) {
      await _sessions.record(hash).delete(db);
      return null;
    }
    return SessionSubject(
      role: asString(record['role']),
      subjectId: asString(record['subjectId']),
      name: asString(record['name']),
      classIds: asStringList(record['classIds']),
      classId: asString(record['classId']),
    );
  }

  Future<void> deleteSession(String token) async {
    await _sessions.record(sha256OfString(token)).delete(db);
  }

  // -------------------------------------------------------------------------
  // Teachers

  Future<List<TeacherInfo>> allTeachers() async {
    final records = await _teachers.find(db);
    final list = records.map((e) => TeacherInfo.fromJson(e.value.cast<String, dynamic>())).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<TeacherInfo?> teacherById(String id) async {
    final map = await _teachers.record(id).get(db);
    return map == null ? null : TeacherInfo.fromJson(map.cast<String, dynamic>());
  }

  Future<TeacherInfo?> teacherByName(String name) async {
    final normalized = normalizeTeacherName(name);
    final records = await _teachers.find(
      db,
      finder: Finder(filter: Filter.equals('name', normalized)),
    );
    if (records.isEmpty) return null;
    return TeacherInfo.fromJson(records.first.value.cast<String, dynamic>());
  }

  Future<AuthResult> registerTeacher({
    required String name,
    required String pin,
    required String registrationCode,
    required List<String> classIds,
  }) async {
    final normalized = normalizeTeacherName(name);
    if (!isValidTeacherName(normalized)) {
      throw HubException('请输入 1–20 个字符的教师姓名');
    }
    if (!isValidPin(pin)) {
      throw HubException('PIN 必须为 4–6 位数字');
    }
    if (config.registrationRequired &&
        config.registrationCode.isNotEmpty &&
        registrationCode.trim() != config.registrationCode) {
      throw HubException('学校注册码不正确');
    }
    final classes = validateClassIds(classIds);
    if (classes.isEmpty) throw HubException('请至少选择一个任教班级');
    if (await teacherByName(normalized) != null) {
      throw HubException('该姓名已注册，请直接登录', statusCode: 409);
    }
    final pinHash = PinHash.create(pin, iterations: 30000);
    final teacher = TeacherInfo(
      id: newId(),
      name: normalized,
      classIds: classes,
    );
    await _teachers.record(teacher.id).put(db, {
      ...teacher.toJson(),
      'pinSalt': pinHash.salt,
      'pinHash': pinHash.hash,
      'pinIterations': pinHash.iterations,
      'createdAt': nowMs(),
    });
    await _ensureStreamsForTeacher(teacher);
    await _saveConfigIfNeeded();
    return _authForTeacher(teacher);
  }

  Future<AuthResult> loginTeacher({required String name, required String pin}) async {
    final teacher = await teacherByName(name);
    if (teacher == null) throw HubException('教师账号不存在', statusCode: 401);
    if (teacher.disabled) throw HubException('该教师账号已被停用', statusCode: 403);
    final map = await _teachers.record(teacher.id).get(db);
    if (map == null) throw HubException('教师账号不存在', statusCode: 401);
    final ok = verifyPin(
      pin: pin,
      salt: asString(map['pinSalt']),
      hash: asString(map['pinHash']),
      iterations: asInt(map['pinIterations'], 30000),
    );
    if (!ok) throw HubException('PIN 不正确', statusCode: 401);
    await _ensureStreamsForTeacher(teacher);
    return _authForTeacher(teacher);
  }

  Future<TeacherInfo> updateTeacherClasses(
    String teacherId,
    List<String> classIds,
  ) async {
    final teacher = await teacherById(teacherId);
    if (teacher == null) throw HubException('教师账号不存在', statusCode: 404);
    final classes = validateClassIds(classIds);
    if (classes.isEmpty) throw HubException('请至少保留一个任教班级');
    final updated = teacher.copyWith(classIds: classes);
    await _teachers.record(teacherId).put(db, {
      ...(await _teachers.record(teacherId).get(db))!,
      ...updated.toJson(),
    });
    await _ensureStreamsForTeacher(updated);
    // Refresh all active sessions for this teacher so class-scoped operations
    // use the new roster immediately.
    final sessions = await _sessions.find(
      db,
      finder: Finder(filter: Filter.and([
        Filter.equals('role', senderTeacher),
        Filter.equals('subjectId', teacherId),
      ])),
    );
    for (final record in sessions) {
      final value = Map<String, Object?>.from(record.value);
      value['classIds'] = classes;
      await _sessions.record(record.key).put(db, value);
    }
    return updated;
  }

  Future<void> resetTeacherPin(String teacherId, String pin) async {
    if (!isValidPin(pin)) throw HubException('PIN 必须为 4–6 位数字');
    final record = await _teachers.record(teacherId).get(db);
    if (record == null) throw HubException('教师账号不存在', statusCode: 404);
    final hash = PinHash.create(pin, iterations: 30000);
    final value = Map<String, Object?>.from(record)
      ..['pinSalt'] = hash.salt
      ..['pinHash'] = hash.hash
      ..['pinIterations'] = hash.iterations;
    await _teachers.record(teacherId).put(db, value);
    final sessions = await _sessions.find(
      db,
      finder: Finder(filter: Filter.and([
        Filter.equals('role', senderTeacher),
        Filter.equals('subjectId', teacherId),
      ])),
    );
    for (final record in sessions) {
      await _sessions.record(record.key).delete(db);
    }
  }

  Future<void> setTeacherDisabled(String teacherId, bool disabled) async {
    final record = await _teachers.record(teacherId).get(db);
    if (record == null) throw HubException('教师账号不存在', statusCode: 404);
    final value = Map<String, Object?>.from(record)..['disabled'] = disabled;
    await _teachers.record(teacherId).put(db, value);
  }

  Future<List<TeacherInfo>> teachersForClass(String classId) async {
    final teachers = await allTeachers();
    return teachers
        .where((t) => !t.disabled && t.classIds.contains(classId))
        .toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // Classrooms

  Future<ClassroomInfo> registerClassroom({
    required String installId,
    required String classId,
    required String machineName,
  }) async {
    if (parseClassId(classId) == null) throw HubException('无效的班级');
    final id = installId.trim().isEmpty ? newId() : installId.trim();
    final now = nowMs();
    final existing = await _classrooms.record(id).get(db);
    final classroom = ClassroomInfo(
      id: id,
      classId: classId,
      machineName: machineName.trim().isEmpty ? '教室电脑' : machineName.trim(),
      lastSeenAt: now,
      online: true,
    );
    await _classrooms.record(id).put(db, {
      ...(existing ?? {}),
      ...classroom.toJson(),
      'createdAt': asInt(existing?['createdAt'], now),
    });
    await _ensureStreamsForClass(classId);
    return classroom;
  }

  Future<AuthResult> authClassroom(ClassroomInfo classroom) => _authForClassroom(classroom);

  Future<List<ClassroomInfo>> allClassrooms() async {
    final records = await _classrooms.find(db);
    return records.map((e) => ClassroomInfo.fromJson(e.value.cast<String, dynamic>())).toList();
  }

  Future<ClassroomInfo?> classroomById(String id) async {
    final value = await _classrooms.record(id).get(db);
    return value == null ? null : ClassroomInfo.fromJson(value.cast<String, dynamic>());
  }

  Future<List<ClassroomInfo>> classroomsForClass(String classId) async {
    return (await allClassrooms()).where((c) => c.classId == classId).toList();
  }

  Future<void> removeClassroom(String id) async {
    await _classrooms.record(id).delete(db);
  }

  // -------------------------------------------------------------------------
  // Streams

  Future<StreamInfo> ensureStream(String classId, String teacherId) async {
    final streamId = streamIdFor(classId, teacherId);
    final existing = await _streams.record(streamId).get(db);
    if (existing != null) {
      return StreamInfo.fromJson(existing.cast<String, dynamic>());
    }
    final teacher = await teacherById(teacherId);
    final info = parseClassId(classId);
    if (teacher == null || info == null) throw HubException('无效的会话');
    final stream = StreamInfo(
      id: streamId,
      classId: classId,
      teacherId: teacherId,
      teacherName: teacher.name,
      className: info.title,
    );
    await _streams.record(streamId).put(db, stream.toJson());
    return stream;
  }

  Future<void> _ensureStreamsForTeacher(TeacherInfo teacher) async {
    for (final classId in teacher.classIds) {
      await ensureStream(classId, teacher.id);
    }
  }

  Future<void> _ensureStreamsForClass(String classId) async {
    final teachers = await teachersForClass(classId);
    for (final teacher in teachers) {
      await ensureStream(classId, teacher.id);
    }
  }

  Future<StreamInfo?> streamById(String streamId) async {
    final value = await _streams.record(streamId).get(db);
    return value == null ? null : StreamInfo.fromJson(value.cast<String, dynamic>());
  }

  Future<List<StreamInfo>> streamsForTeacher(String teacherId) async {
    final teacher = await teacherById(teacherId);
    final records = await _streams.find(
      db,
      finder: Finder(filter: Filter.equals('teacherId', teacherId)),
    );
    final streams = records.map((e) => StreamInfo.fromJson(e.value.cast<String, dynamic>())).toList();
    if (teacher != null) {
      for (final classId in teacher.classIds) {
        await ensureStream(classId, teacherId);
      }
    }
    final refreshed = await _streams.find(
      db,
      finder: Finder(filter: Filter.equals('teacherId', teacherId)),
    );
    final result = <StreamInfo>[];
    for (final record in refreshed) {
      final stream = StreamInfo.fromJson(record.value.cast<String, dynamic>());
      if (teacher != null && !teacher.classIds.contains(stream.classId)) continue;
      result.add(stream);
    }
    // Preserve a deterministic class order.
    result.sort((a, b) {
      final ai = allClasses.indexWhere((e) => e.id == a.classId);
      final bi = allClasses.indexWhere((e) => e.id == b.classId);
      return ai.compareTo(bi);
    });
    if (result.isEmpty && streams.isNotEmpty) {
      result.addAll(streams);
    }
    return result;
  }

  Future<List<StreamInfo>> streamsForClass(String classId) async {
    await _ensureStreamsForClass(classId);
    final teachers = await teachersForClass(classId);
    final records = await _streams.find(
      db,
      finder: Finder(filter: Filter.equals('classId', classId)),
    );
    final byTeacher = <String, StreamInfo>{};
    for (final record in records) {
      final stream = StreamInfo.fromJson(record.value.cast<String, dynamic>());
      byTeacher[stream.teacherId] = stream;
    }
    final result = <StreamInfo>[];
    for (final teacher in teachers) {
      final stream = byTeacher[teacher.id] ??
          await ensureStream(classId, teacher.id);
      result.add(stream);
    }
    for (final stream in byTeacher.values) {
      if (result.every((e) => e.id != stream.id) && stream.lastMessageAt > 0) {
        result.add(stream);
      }
    }
    result.sort((a, b) => a.teacherName.compareTo(b.teacherName));
    return result;
  }

  Future<List<StreamInfo>> allStreams() async {
    final records = await _streams.find(db);
    return records.map((e) => StreamInfo.fromJson(e.value.cast<String, dynamic>())).toList();
  }

  // -------------------------------------------------------------------------
  // Messages

  Future<Message> appendMessage(Message input, SessionSubject subject) {
    return _serial(() async {
      final stream = await streamById(input.streamId);
      if (stream == null) throw HubException('会话不存在', statusCode: 404);

      if (subject.isTeacher) {
        final teacher = await teacherById(subject.subjectId);
        if (teacher == null || teacher.disabled) {
          throw HubException('教师账号不可用', statusCode: 403);
        }
        if (!teacher.classIds.contains(stream.classId) ||
            stream.teacherId != teacher.id) {
          throw HubException('没有该班级的发送权限', statusCode: 403);
        }
        if (input.kind != kindChat &&
            input.kind != kindNotice &&
            input.kind != kindFile) {
          throw HubException('不支持的消息类型');
        }
      } else if (subject.isClassroom) {
        if (subject.classId != stream.classId) {
          throw HubException('没有该会话的发送权限', statusCode: 403);
        }
        if (input.kind != kindChat) {
          throw HubException('教室端只能发送普通消息');
        }
      } else {
        throw HubException('未认证', statusCode: 401);
      }

      final existing = await _messageIndex.record(input.id).get(db);
      if (existing != null) {
        final seq = asInt(existing['seq']);
        final stored = await _messagesOf(stream.id).record(seq).get(db);
        if (stored != null) {
          return Message.fromJson(stored.cast<String, dynamic>());
        }
      }

      if (input.text.length > maxTextLength) throw HubException('消息过长');
      if (input.title.length > maxTitleLength) throw HubException('标题过长');
      var fileInfo = input.file;
      if (input.kind == kindFile) {
        if (fileInfo == null) throw HubException('缺少文件信息');
        final storedFile = await fileById(fileInfo.id);
        if (storedFile == null) throw HubException('文件不存在', statusCode: 404);
        fileInfo = storedFile;
      }
      var closeMode = input.closeMode == closeModeAuto ? closeModeAuto : closeModeManual;
      var autoClose = input.autoCloseSec.clamp(1, maxAutoCloseSeconds);
      if (closeMode == closeModeManual) autoClose = defaultAutoCloseSeconds;

      final now = nowMs();
      var createdAt = input.createdAt;
      if (createdAt <= 0 || createdAt > now + const Duration(minutes: 5).inMilliseconds) {
        createdAt = now;
      }
      final seq = await _nextSeq();
      final message = Message(
        id: input.id.isEmpty ? newId() : input.id,
        streamId: stream.id,
        classId: stream.classId,
        teacherId: stream.teacherId,
        senderType: subject.isTeacher ? senderTeacher : senderClassroom,
        senderId: subject.subjectId,
        senderName: subject.isTeacher ? subject.name : '教室端',
        kind: input.kind,
        text: input.text,
        title: input.title,
        closeMode: closeMode,
        autoCloseSec: autoClose,
        sound: input.sound,
        file: fileInfo,
        createdAt: createdAt,
        seq: seq,
      );
      final map = message.toJson();
      await _messagesOf(stream.id).record(seq).put(db, map);
      await _messageIndex.record(message.id).put(db, {
        'streamId': stream.id,
        'seq': seq,
      });
      if (message.createdAt >= stream.lastMessageAt) {
        await _streams.record(stream.id).put(
          db,
          stream
              .copyWith(
                lastMessageAt: message.createdAt,
                lastMessagePreview: message.preview,
              )
              .toJson(),
        );
      }
      return message;
    });
  }

  Future<int> _nextSeq() async {
    final current = await _meta.record('seq').get(db) ?? 0;
    final next = current + 1;
    await _meta.record('seq').put(db, next);
    return next;
  }

  Future<List<Message>> messagesForStream(
    String streamId, {
    int afterSeq = 0,
    int limit = 500,
  }) async {
    final store = _messagesOf(streamId);
    final records = await store.find(
      db,
      finder: Finder(
        filter: Filter.greaterThan('seq', afterSeq),
        sortOrders: [SortOrder('seq')],
      ),
    );
    final messages = records
        .map((e) => Message.fromJson(e.value.cast<String, dynamic>()))
        .toList(growable: false);
    if (messages.length <= limit) return messages;
    if (afterSeq > 0) return messages.take(limit).toList(growable: false);
    return messages.skip(messages.length - limit).toList(growable: false);
  }

  Future<Message?> messageById(String id) async {
    final index = await _messageIndex.record(id).get(db);
    if (index == null) return null;
    final streamId = asString(index['streamId']);
    final seq = asInt(index['seq']);
    final value = await _messagesOf(streamId).record(seq).get(db);
    return value == null ? null : Message.fromJson(value.cast<String, dynamic>());
  }

  Future<void> ackMessage(String messageId, String recipientId) async {
    await _acks.record('$messageId::$recipientId').put(db, {
      'messageId': messageId,
      'recipientId': recipientId,
      'at': nowMs(),
    });
  }

  Future<List<DeliveryInfo>> acksFor(String messageId) async {
    final records = await _acks.find(
      db,
      finder: Finder(filter: Filter.equals('messageId', messageId)),
    );
    return records
        .map((e) => DeliveryInfo.fromJson(e.value.cast<String, dynamic>()))
        .toList();
  }

  Future<int> messageCount() async {
    // Count only indexed messages; this is an admin metric, not a hot path.
    return (await _messageIndex.find(db)).length;
  }

  // -------------------------------------------------------------------------
  // Files

  Future<FileInfo> registerFile({
    required String name,
    required int size,
    required String sha256,
    required String mime,
  }) async {
    if (size <= 0) throw HubException('文件为空');
    if (size > config.maxFileBytes) {
      throw HubException('文件超过服务器上限 ${formatFileSize(config.maxFileBytes)}', statusCode: 413);
    }
    if (sha256.isNotEmpty) {
      final existingRef = await _filesBySha.record(sha256).get(db);
      if (existingRef != null) {
        final id = asString(existingRef['fileId']);
        final existing = await fileById(id);
        if (existing != null && !existing.expired) return existing;
      }
    }
    final id = newId();
    final file = FileInfo(
      id: id,
      name: sanitizeFileName(name),
      size: size,
      sha256: sha256,
      mime: mime,
      expiresAt: config.retentionDays > 0
          ? nowMs() + Duration(days: config.retentionDays).inMilliseconds
          : null,
    );
    await _files.record(id).put(db, file.toJson());
    if (sha256.isNotEmpty) {
      await _filesBySha.record(sha256).put(db, {'fileId': id});
    }
    return file;
  }

  Future<FileInfo?> fileById(String id) async {
    final value = await _files.record(id).get(db);
    return value == null ? null : FileInfo.fromJson(value.cast<String, dynamic>());
  }

  Future<List<FileInfo>> allFiles() async {
    final records = await _files.find(db);
    return records.map((e) => FileInfo.fromJson(e.value.cast<String, dynamic>())).toList();
  }

  Future<FileInfo> writeFileContent(
    String fileId,
    Stream<List<int>> stream,
  ) async {
    final existing = await fileById(fileId);
    if (existing == null) throw HubException('文件不存在', statusCode: 404);
    final written = await files.writeStream(
      fileId: fileId,
      name: existing.name,
      mime: existing.mime,
      stream: stream,
      expectedSize: existing.size,
      expectedSha256: existing.sha256,
      expiresAt: existing.expiresAt,
    );
    await _files.record(fileId).put(db, written.toJson());
    if (written.sha256.isNotEmpty) {
      await _filesBySha.record(written.sha256).put(db, {'fileId': fileId});
    }
    return written;
  }

  Future<void> cleanupExpiredFiles() async {
    final all = await allFiles();
    final now = nowMs();
    for (final file in all) {
      if (file.expiresAt != null && file.expiresAt! < now) {
        await files.deleteBlob(file.id);
      }
    }
  }

  Future<int> fileBytes() => files.totalBytes();

  // -------------------------------------------------------------------------
  // Admin

  Future<AdminSnapshot> adminSnapshot({
    List<PresenceInfo> onlineDevices = const [],
  }) async {
    final fileList = await allFiles();
    return AdminSnapshot(
      hub: HubInfo(
        id: config.id,
        name: config.name,
        version: appVersion,
        serverTimeMs: nowMs(),
        registrationCodeRequired: config.registrationRequired,
      ),
      teachers: await allTeachers(),
      classrooms: await allClassrooms(),
      registrationCode: config.registrationCode,
      fileCount: fileList.length,
      fileBytes: await fileBytes(),
      startedAt: startedAt,
      onlineDevices: onlineDevices,
      maxFileBytes: config.maxFileBytes,
      retentionDays: config.retentionDays,
    );
  }

  Future<void> setRegistrationCode(String code, {bool required = true}) async {
    config.registrationCode = code.trim();
    config.registrationRequired = required;
    await _saveConfig();
  }

  Future<void> updateSettings({
    String? name,
    int? maxFileBytes,
    int? retentionDays,
  }) async {
    if (name != null && name.trim().isNotEmpty) config.name = name.trim();
    if (maxFileBytes != null && maxFileBytes > 0) config.maxFileBytes = maxFileBytes;
    if (retentionDays != null && retentionDays >= 0) config.retentionDays = retentionDays;
    await _saveConfig();
  }

  Future<void> _saveConfigIfNeeded() async {
    // touch config once on first mutation; keeps config file in sync.
    await _saveConfig();
  }

  Future<bool> verifyAdminPin(String pin) async => config.verifyAdminPin(pin);

  Future<void> changeAdminPin(String pin) async {
    if (!isValidPin(pin)) throw HubException('管理员 PIN 必须为 4–6 位数字');
    config.setAdminPin(pin);
    await _saveConfig();
  }

  Future<void> removeTeacher(String id) async {
    await _teachers.record(id).delete(db);
  }
}
