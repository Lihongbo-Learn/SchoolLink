import 'constants.dart';

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}

String asString(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

int asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return fallback;
}

List<String> asStringList(Object? value) {
  if (value is List) {
    return value.whereType<String>().toList(growable: false);
  }
  return const [];
}

DateTime dateTimeFromMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

class HubInfo {
  const HubInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.serverTimeMs,
    this.registrationCodeRequired = true,
  });

  final String id;
  final String name;
  final String version;
  final int serverTimeMs;
  final bool registrationCodeRequired;

  factory HubInfo.fromJson(Map<String, dynamic> json) => HubInfo(
        id: asString(json['id']),
        name: asString(json['name'], appName),
        version: asString(json['version'], appVersion),
        serverTimeMs: asInt(json['serverTimeMs'], DateTime.now().millisecondsSinceEpoch),
        registrationCodeRequired: asBool(json['registrationCodeRequired'], true),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'serverTimeMs': serverTimeMs,
        'registrationCodeRequired': registrationCodeRequired,
      };
}

class ClassInfo {
  const ClassInfo({
    required this.id,
    required this.grade,
    required this.number,
    required this.title,
  });

  final String id;
  final int grade;
  final int number;
  final String title;

  factory ClassInfo.fromJson(Map<String, dynamic> json) => ClassInfo(
        id: asString(json['id']),
        grade: asInt(json['grade'], 1),
        number: asInt(json['number'], 9),
        title: asString(json['title']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'grade': grade,
        'number': number,
        'title': title,
      };
}

class TeacherInfo {
  const TeacherInfo({
    required this.id,
    required this.name,
    required this.classIds,
    this.disabled = false,
  });

  final String id;
  final String name;
  final List<String> classIds;
  final bool disabled;

  factory TeacherInfo.fromJson(Map<String, dynamic> json) => TeacherInfo(
        id: asString(json['id']),
        name: asString(json['name']),
        classIds: asStringList(json['classIds']),
        disabled: asBool(json['disabled']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'classIds': classIds,
        'disabled': disabled,
      };

  TeacherInfo copyWith({String? name, List<String>? classIds, bool? disabled}) =>
      TeacherInfo(
        id: id,
        name: name ?? this.name,
        classIds: classIds ?? this.classIds,
        disabled: disabled ?? this.disabled,
      );
}

class ClassroomInfo {
  const ClassroomInfo({
    required this.id,
    required this.classId,
    required this.machineName,
    required this.lastSeenAt,
    this.online = false,
  });

  final String id;
  final String classId;
  final String machineName;
  final int lastSeenAt;
  final bool online;

  factory ClassroomInfo.fromJson(Map<String, dynamic> json) => ClassroomInfo(
        id: asString(json['id']),
        classId: asString(json['classId']),
        machineName: asString(json['machineName']),
        lastSeenAt: asInt(json['lastSeenAt']),
        online: asBool(json['online']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'classId': classId,
        'machineName': machineName,
        'lastSeenAt': lastSeenAt,
        'online': online,
      };
}

class StreamInfo {
  const StreamInfo({
    required this.id,
    required this.classId,
    required this.teacherId,
    required this.teacherName,
    required this.className,
    this.lastMessageAt = 0,
    this.lastMessagePreview = '',
  });

  final String id;
  final String classId;
  final String teacherId;
  final String teacherName;
  final String className;
  final int lastMessageAt;
  final String lastMessagePreview;

  factory StreamInfo.fromJson(Map<String, dynamic> json) => StreamInfo(
        id: asString(json['id']),
        classId: asString(json['classId']),
        teacherId: asString(json['teacherId']),
        teacherName: asString(json['teacherName']),
        className: asString(json['className']),
        lastMessageAt: asInt(json['lastMessageAt']),
        lastMessagePreview: asString(json['lastMessagePreview']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'classId': classId,
        'teacherId': teacherId,
        'teacherName': teacherName,
        'className': className,
        'lastMessageAt': lastMessageAt,
        'lastMessagePreview': lastMessagePreview,
      };

  StreamInfo copyWith({int? lastMessageAt, String? lastMessagePreview}) => StreamInfo(
        id: id,
        classId: classId,
        teacherId: teacherId,
        teacherName: teacherName,
        className: className,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      );
}

class FileInfo {
  const FileInfo({
    required this.id,
    required this.name,
    required this.size,
    required this.sha256,
    this.mime = 'application/octet-stream',
    this.expiresAt,
  });

  final String id;
  final String name;
  final int size;
  final String sha256;
  final String mime;
  final int? expiresAt;

  factory FileInfo.fromJson(Map<String, dynamic> json) => FileInfo(
        id: asString(json['id']),
        name: sanitizeFileName(asString(json['name'], 'file')),
        size: asInt(json['size']),
        sha256: asString(json['sha256']),
        mime: asString(json['mime'], 'application/octet-stream'),
        expiresAt: json['expiresAt'] == null ? null : asInt(json['expiresAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'sha256': sha256,
        'mime': mime,
        if (expiresAt != null) 'expiresAt': expiresAt,
      };

  bool get expired =>
      expiresAt != null && DateTime.now().millisecondsSinceEpoch > expiresAt!;
}

class Message {
  const Message({
    required this.id,
    required this.streamId,
    required this.classId,
    required this.teacherId,
    required this.senderType,
    required this.senderId,
    required this.senderName,
    required this.kind,
    required this.createdAt,
    this.text = '',
    this.title = '',
    this.closeMode = closeModeManual,
    this.autoCloseSec = defaultAutoCloseSeconds,
    this.sound = true,
    this.file,
    this.seq,
  });

  final String id;
  final String streamId;
  final String classId;
  final String teacherId;
  final String senderType;
  final String senderId;
  final String senderName;
  final String kind;
  final String text;
  final String title;
  final String closeMode;
  final int autoCloseSec;
  final bool sound;
  final FileInfo? file;
  final int createdAt;
  final int? seq;

  bool get isNotice => kind == kindNotice;
  bool get isFile => kind == kindFile;
  bool get isChat => kind == kindChat;
  bool get fromTeacher => senderType == senderTeacher;
  bool get fromClassroom => senderType == senderClassroom;
  bool get manualClose => closeMode == closeModeManual;

  String get preview {
    if (isFile) return file == null ? '文件' : '[文件] ${file!.name}';
    if (isNotice) return title.isEmpty ? text : title;
    return text;
  }

  Message copyWith({int? seq}) => Message(
        id: id,
        streamId: streamId,
        classId: classId,
        teacherId: teacherId,
        senderType: senderType,
        senderId: senderId,
        senderName: senderName,
        kind: kind,
        createdAt: createdAt,
        text: text,
        title: title,
        closeMode: closeMode,
        autoCloseSec: autoCloseSec,
        sound: sound,
        file: file,
        seq: seq ?? this.seq,
      );

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: asString(json['id']),
        streamId: asString(json['streamId']),
        classId: asString(json['classId']),
        teacherId: asString(json['teacherId']),
        senderType: asString(json['senderType'], senderTeacher),
        senderId: asString(json['senderId']),
        senderName: asString(json['senderName']),
        kind: asString(json['kind'], kindChat),
        createdAt: asInt(json['createdAt'], DateTime.now().millisecondsSinceEpoch),
        text: asString(json['text']),
        title: asString(json['title']),
        closeMode: asString(json['closeMode'], closeModeManual),
        autoCloseSec: asInt(json['autoCloseSec'], defaultAutoCloseSeconds),
        sound: asBool(json['sound'], true),
        file: json['file'] == null ? null : FileInfo.fromJson(asMap(json['file'])),
        seq: json['seq'] == null ? null : asInt(json['seq']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'streamId': streamId,
        'classId': classId,
        'teacherId': teacherId,
        'senderType': senderType,
        'senderId': senderId,
        'senderName': senderName,
        'kind': kind,
        'text': text,
        'title': title,
        'closeMode': closeMode,
        'autoCloseSec': autoCloseSec,
        'sound': sound,
        if (file != null) 'file': file!.toJson(),
        'createdAt': createdAt,
        if (seq != null) 'seq': seq,
      };
}

class AuthResult {
  const AuthResult({
    required this.token,
    required this.role,
    required this.classIds,
    this.teacher,
    this.classroom,
    this.meshKeys = const {},
  });

  final String token;
  final String role;
  final List<String> classIds;
  final TeacherInfo? teacher;
  final ClassroomInfo? classroom;
  final Map<String, String> meshKeys;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        token: asString(json['token']),
        role: asString(json['role']),
        classIds: asStringList(json['classIds']),
        teacher: json['teacher'] == null ? null : TeacherInfo.fromJson(asMap(json['teacher'])),
        classroom: json['classroom'] == null
            ? null
            : ClassroomInfo.fromJson(asMap(json['classroom'])),
        meshKeys: asStringMap(json['meshKeys']),
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'role': role,
        'classIds': classIds,
        if (teacher != null) 'teacher': teacher!.toJson(),
        if (classroom != null) 'classroom': classroom!.toJson(),
        'meshKeys': meshKeys,
      };
}

Map<String, String> asStringMap(Object? value) {
  final result = <String, String>{};
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is String && entry.value is String) {
        result[entry.key as String] = entry.value as String;
      }
    }
  }
  return result;
}

class Bootstrap {
  const Bootstrap({
    required this.hub,
    required this.serverTimeMs,
    required this.classes,
    required this.teachers,
    required this.classrooms,
    required this.streams,
    this.teacher,
    this.classroom,
    this.meshKeys = const {},
  });

  final HubInfo hub;
  final int serverTimeMs;
  final List<ClassInfo> classes;
  final List<TeacherInfo> teachers;
  final List<ClassroomInfo> classrooms;
  final List<StreamInfo> streams;
  final TeacherInfo? teacher;
  final ClassroomInfo? classroom;
  final Map<String, String> meshKeys;

  factory Bootstrap.fromJson(Map<String, dynamic> json) => Bootstrap(
        hub: HubInfo.fromJson(asMap(json['hub'])),
        serverTimeMs: asInt(json['serverTimeMs'], DateTime.now().millisecondsSinceEpoch),
        classes: asMapList(json['classes']).map(ClassInfo.fromJson).toList(),
        teachers: asMapList(json['teachers']).map(TeacherInfo.fromJson).toList(),
        classrooms: asMapList(json['classrooms']).map(ClassroomInfo.fromJson).toList(),
        streams: asMapList(json['streams']).map(StreamInfo.fromJson).toList(),
        teacher: json['teacher'] == null ? null : TeacherInfo.fromJson(asMap(json['teacher'])),
        classroom:
            json['classroom'] == null ? null : ClassroomInfo.fromJson(asMap(json['classroom'])),
        meshKeys: asStringMap(json['meshKeys']),
      );

  Map<String, dynamic> toJson() => {
        'hub': hub.toJson(),
        'serverTimeMs': serverTimeMs,
        'classes': classes.map((e) => e.toJson()).toList(),
        'teachers': teachers.map((e) => e.toJson()).toList(),
        'classrooms': classrooms.map((e) => e.toJson()).toList(),
        'streams': streams.map((e) => e.toJson()).toList(),
        if (teacher != null) 'teacher': teacher!.toJson(),
        if (classroom != null) 'classroom': classroom!.toJson(),
        'meshKeys': meshKeys,
      };
}

List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is List) {
    return value.map(asMap).where((e) => e.isNotEmpty).toList(growable: false);
  }
  return const [];
}

class PresenceInfo {
  const PresenceInfo({
    required this.deviceId,
    required this.role,
    required this.classId,
    this.teacherId = '',
    this.online = true,
    this.machineName = '',
  });

  final String deviceId;
  final String role;
  final String classId;
  final String teacherId;
  final bool online;
  final String machineName;

  factory PresenceInfo.fromJson(Map<String, dynamic> json) => PresenceInfo(
        deviceId: asString(json['deviceId']),
        role: asString(json['role']),
        classId: asString(json['classId']),
        teacherId: asString(json['teacherId']),
        online: asBool(json['online'], true),
        machineName: asString(json['machineName']),
      );

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'role': role,
        'classId': classId,
        'teacherId': teacherId,
        'online': online,
        'machineName': machineName,
      };
}

class DeliveryInfo {
  const DeliveryInfo({
    required this.messageId,
    required this.recipientId,
    required this.state,
    required this.at,
  });

  final String messageId;
  final String recipientId;
  final String state;
  final int at;

  factory DeliveryInfo.fromJson(Map<String, dynamic> json) => DeliveryInfo(
        messageId: asString(json['messageId']),
        recipientId: asString(json['recipientId']),
        state: asString(json['state'], 'delivered'),
        at: asInt(json['at']),
      );

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'recipientId': recipientId,
        'state': state,
        'at': at,
      };
}

class AdminSnapshot {
  const AdminSnapshot({
    required this.hub,
    required this.teachers,
    required this.classrooms,
    required this.registrationCode,
    required this.fileCount,
    required this.fileBytes,
    required this.startedAt,
    this.onlineDevices = const [],
    this.maxFileBytes = 2 * 1024 * 1024 * 1024,
    this.retentionDays = 90,
  });

  final HubInfo hub;
  final List<TeacherInfo> teachers;
  final List<ClassroomInfo> classrooms;
  final String registrationCode;
  final int fileCount;
  final int fileBytes;
  final int startedAt;
  final List<PresenceInfo> onlineDevices;
  final int maxFileBytes;
  final int retentionDays;

  factory AdminSnapshot.fromJson(Map<String, dynamic> json) => AdminSnapshot(
        hub: HubInfo.fromJson(asMap(json['hub'])),
        teachers: asMapList(json['teachers']).map(TeacherInfo.fromJson).toList(),
        classrooms: asMapList(json['classrooms']).map(ClassroomInfo.fromJson).toList(),
        registrationCode: asString(json['registrationCode']),
        fileCount: asInt(json['fileCount']),
        fileBytes: asInt(json['fileBytes']),
        startedAt: asInt(json['startedAt']),
        onlineDevices:
            asMapList(json['onlineDevices']).map(PresenceInfo.fromJson).toList(),
        maxFileBytes: asInt(json['maxFileBytes'], 2 * 1024 * 1024 * 1024),
        retentionDays: asInt(json['retentionDays'], 90),
      );

  Map<String, dynamic> toJson() => {
        'hub': hub.toJson(),
        'teachers': teachers.map((e) => e.toJson()).toList(),
        'classrooms': classrooms.map((e) => e.toJson()).toList(),
        'registrationCode': registrationCode,
        'fileCount': fileCount,
        'fileBytes': fileBytes,
        'startedAt': startedAt,
        'onlineDevices': onlineDevices.map((e) => e.toJson()).toList(),
        'maxFileBytes': maxFileBytes,
        'retentionDays': retentionDays,
      };
}
