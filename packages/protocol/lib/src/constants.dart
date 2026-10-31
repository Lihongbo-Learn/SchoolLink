import 'models.dart';

const int protocolVersion = 1;
const int hubHttpPort = 8421;
const int hubUdpPort = 8421;
const int peerPort = 8422;
const int peerDiscoveryPort = 8424;

const String appName = '校联';
const String appVersion = '0.2.0_dev';

const List<int> gradeNumbers = [1, 2, 3];
const List<int> classNumbers = [9, 10, 11, 12, 13, 14, 15, 16];

String gradeName(int grade) {
  switch (grade) {
    case 1:
      return '高一';
    case 2:
      return '高二';
    case 3:
      return '高三';
    default:
      return '高$grade';
  }
}

String makeClassId(int grade, int number) =>
    'g$grade-${number.toString().padLeft(2, '0')}';

ClassInfo? parseClassId(String id) {
  final m = RegExp(r'^g([1-3])-(\d{2})$').firstMatch(id);
  if (m == null) return null;
  final grade = int.parse(m.group(1)!);
  final number = int.parse(m.group(2)!);
  if (!classNumbers.contains(number)) return null;
  return ClassInfo(
    id: id,
    grade: grade,
    number: number,
    title: '${gradeName(grade)}$number班',
  );
}

final List<ClassInfo> allClasses = [
  for (final g in gradeNumbers)
    for (final n in classNumbers) parseClassId(makeClassId(g, n))!,
];

const String kindChat = 'chat';
const String kindNotice = 'notice';
const String kindFile = 'file';
const String kindSystem = 'system';

const String senderTeacher = 'teacher';
const String senderClassroom = 'classroom';
const String senderSystem = 'system';

const String closeModeManual = 'manual';
const String closeModeAuto = 'auto';

const int maxTextLength = 4000;
const int maxTitleLength = 80;
const int maxFileNameLength = 180;
const int defaultAutoCloseSeconds = 15;
const int maxAutoCloseSeconds = 300;
const int noticeFreshnessMs = 120000;

String streamIdFor(String classId, String teacherId) =>
    '$classId::$teacherId';

String? classIdFromStream(String streamId) {
  final index = streamId.indexOf('::');
  return index <= 0 ? null : streamId.substring(0, index);
}

String? teacherIdFromStream(String streamId) {
  final index = streamId.indexOf('::');
  return index < 0 ? null : streamId.substring(index + 2);
}

bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

bool isValidTeacherName(String name) {
  final value = name.trim();
  return value.isNotEmpty && value.length <= 20;
}

String normalizeTeacherName(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ');

String sanitizeFileName(String raw) {
  var name = raw.trim();
  if (name.isEmpty) return 'file';
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
  if (name.length > maxFileNameLength) {
    final dot = name.lastIndexOf('.');
    if (dot > 0 && name.length - dot <= 12) {
      final ext = name.substring(dot);
      name = name.substring(0, maxFileNameLength - ext.length) + ext;
    } else {
      name = name.substring(0, maxFileNameLength);
    }
  }
  return name;
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}
