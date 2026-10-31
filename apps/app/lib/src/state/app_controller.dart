import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_link_protocol/protocol.dart';

import '../data/local_store.dart';
import '../services/discovered_hub.dart';
import '../services/discovery.dart';
import '../services/hub_api.dart';
import '../services/hub_socket.dart';
import '../services/peer_info.dart';
import '../services/peer_service.dart';
import '../services/platform_service.dart';

enum AppPhase { loading, onboarding, teacherAuth, teacherHome, classroomHome, reconnect }

enum MessageSendState { sending, sent, failed }

class AppController extends ChangeNotifier {
  AppController();

  late SharedPreferences _prefs;
  late LocalStore _local;
  HubApi? _api;
  HubSocket? _socket;
  PeerService? _peer;
  AudioPlayer? _player;
  bool _flushingOutbox = false;
  bool _disposed = false;

  AppPhase phase = AppPhase.loading;
  String? mode;
  int? grade;
  int? classNo;
  String? classId;
  String hubUrl = '';
  String? token;
  String? installId;
  String deviceName = '本机';

  TeacherInfo? teacher;
  ClassroomInfo? classroom;
  HubInfo? hubInfo;
  List<StreamInfo> streams = const [];
  List<TeacherInfo> classTeachers = const [];
  List<ClassroomInfo> classClassrooms = const [];
  Map<String, String> meshKeys = const {};

  bool connected = false;
  String? connectionMessage;
  String? error;
  bool busy = false;
  String? busyText;
  bool discovering = false;
  List<DiscoveredHub> discoveredHubs = const [];

  Message? activeNotice;
  final List<Message> _noticeQueue = [];
  Timer? _noticeTimer;
  final Map<String, List<Message>> _messagesByStream = {};
  final Map<String, int> _lastRead = {};
  final Map<String, String> _filePaths = {};
  final Map<String, MessageSendState> _sendStates = {};
  final Set<String> _downloadingFiles = {};
  final Map<String, Set<String>> _deliveries = {};
  final Set<String> _acksSent = {};
  int _serverOffsetMs = 0;
  String? currentStreamId;
  Timer? _rosterDebounce;

  bool get isClassroom => mode == 'classroom';
  bool get isTeacher => mode == 'teacher';
  bool get canSend => token != null && _api != null;
  bool get isWeb => kIsWeb;

  String get currentClassTitle {
    final id = classId;
    if (id == null) return '';
    return parseClassId(id)?.title ?? id;
  }

  StreamInfo? get currentStream {
    final id = currentStreamId;
    if (id == null) return null;
    for (final stream in streams) {
      if (stream.id == id) return stream;
    }
    return streams.isEmpty ? null : streams.first;
  }

  List<Message> messagesFor(String streamId) =>
      List<Message>.unmodifiable(_messagesByStream[streamId] ?? const <Message>[]);

  List<Message> get allNotices {
    final notices = <Message>[];
    for (final list in _messagesByStream.values) {
      notices.addAll(list.where((m) => m.isNotice));
    }
    notices.sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return notices;
  }

  int get noticeQueueLength => _noticeQueue.length;

  String? get myId => isClassroom ? (classroom?.id ?? installId) : teacher?.id;

  String? get myName => isClassroom ? '教室端' : teacher?.name;

  String? get myClassId => isClassroom ? classId : null;

  int get serverNowMs => nowMs() + _serverOffsetMs;

  String get serverOffsetLabel {
    final offset = (_serverOffsetMs / 1000).round();
    if (offset == 0) return '与本机时间同步';
    return offset > 0 ? '服务器快 ${offset}s' : '服务器慢 ${-offset}s';
  }

  int unreadFor(String streamId) {
    final lastRead = _lastRead[streamId] ?? 0;
    final list = _messagesByStream[streamId] ?? const <Message>[];
    var count = 0;
    for (final message in list) {
      if (message.createdAt <= lastRead) continue;
      if (_isMine(message)) continue;
      count += 1;
    }
    return count;
  }

  bool onlineTeacher(String teacherId) =>
      _onlineTeachers.contains(teacherId) || _peerOnlineTeachers.contains(teacherId);

  bool onlineClass(String targetClassId) =>
      _onlineClasses.contains(targetClassId) || _peerOnlineClasses.contains(targetClassId);

  bool get hasDirectPeers =>
      _peerOnlineTeachers.isNotEmpty || _peerOnlineClasses.isNotEmpty;

  final Set<String> _onlineTeachers = {};
  final Set<String> _onlineClasses = {};
  final Set<String> _peerOnlineTeachers = {};
  final Set<String> _peerOnlineClasses = {};

  String? sendStateOf(String messageId) => _sendStates[messageId]?.name;

  String? filePathOf(String messageId) => _filePaths[messageId];

  bool downloading(String messageId) => _downloadingFiles.contains(messageId);

  int deliveryCount(String messageId) => _deliveries[messageId]?.length ?? 0;

  bool _isMine(Message message) {
    final id = myId;
    if (id == null) return false;
    return message.senderId == id ||
        (message.senderType == (isClassroom ? senderClassroom : senderTeacher) &&
            message.senderId == id);
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _local = await LocalStore.open();
    installId = _prefs.getString('installId');
    if (installId == null || installId!.isEmpty) {
      installId = newId();
      await _prefs.setString('installId', installId!);
    }
    deviceName = (await platform.machineName()).trim();
    if (deviceName.isEmpty) deviceName = '本机';

    mode = _prefs.getString('mode');
    grade = _prefs.getInt('grade');
    classNo = _prefs.getInt('classNo');
    classId = _prefs.getString('classId');
    hubUrl = _prefs.getString('hubUrl') ?? '';
    token = _prefs.getString('token');
    final savedTeacherId = _prefs.getString('teacherId');
    final savedTeacherName = _prefs.getString('teacherName');

    if (kIsWeb && hubUrl.isEmpty) {
      final origin = Uri.base.origin;
      if (origin.startsWith('http')) hubUrl = origin;
    }

    if (mode == null || mode!.isEmpty) {
      phase = AppPhase.onboarding;
      notifyListeners();
      return;
    }

    if (mode == 'teacher' && (token == null || hubUrl.isEmpty)) {
      phase = AppPhase.teacherAuth;
      notifyListeners();
      return;
    }
    if (mode == 'classroom' && (token == null || hubUrl.isEmpty)) {
      phase = AppPhase.reconnect;
      notifyListeners();
      return;
    }

    await _restoreSession(savedTeacherId: savedTeacherId, savedTeacherName: savedTeacherName);
  }

  Future<void> _restoreSession({
    String? savedTeacherId,
    String? savedTeacherName,
  }) async {
    _api = HubApi(baseUrl: hubUrl, token: token);
    final cached = await _loadCachedBootstrap();
    if (cached != null) {
      _applyBootstrap(cached);
      _setPhaseForMode();
      notifyListeners();
      await _loadLocalMessages();
      await _configurePeer();
    }
    try {
      final bootstrap = await _api!.bootstrap();
      _applyBootstrap(bootstrap);
      await _persistProfile();
      _setPhaseForMode();
      notifyListeners();
      _connectSocket();
      await _configurePeer();
      await _loadAllMessages();
      unawaited(_flushOutbox());
    } on HubApiException catch (e) {
      connectionMessage = e.message;
      if (e.statusCode == 401) {
        await _clearToken();
        phase = isClassroom ? AppPhase.reconnect : AppPhase.teacherAuth;
      } else {
        _setPhaseForMode();
        await _loadLocalMessages();
      }
      notifyListeners();
    } catch (e) {
      connectionMessage = '无法连接服务器';
      _setPhaseForMode();
      await _loadLocalMessages();
      notifyListeners();
    }
  }

  void _setPhaseForMode() {
    if (mode == 'classroom') {
      phase = AppPhase.classroomHome;
    } else if (mode == 'teacher') {
      phase = AppPhase.teacherHome;
    } else {
      phase = AppPhase.onboarding;
    }
  }

  void _applyBootstrap(Bootstrap bootstrap) {
    hubInfo = bootstrap.hub;
    _serverOffsetMs = bootstrap.serverTimeMs - nowMs();
    teacher = bootstrap.teacher ?? teacher;
    classroom = bootstrap.classroom ?? classroom;
    streams = List<StreamInfo>.from(bootstrap.streams);
    classTeachers = List<TeacherInfo>.from(bootstrap.teachers);
    classClassrooms = List<ClassroomInfo>.from(bootstrap.classrooms);
    meshKeys = Map<String, String>.from(bootstrap.meshKeys);
    if (mode == 'classroom' && classroom != null) {
      classId = classroom!.classId;
      grade = parseClassId(classId!)?.grade;
      classNo = parseClassId(classId!)?.number;
    }
    if (mode == 'teacher' && teacher != null) {
      _prefs.setString('teacherId', teacher!.id);
      _prefs.setString('teacherName', teacher!.name);
      _prefs.setStringList('teacherClassIds', teacher!.classIds);
    }
    _cacheBootstrap(bootstrap);
    if (currentStreamId != null &&
        !streams.any((stream) => stream.id == currentStreamId)) {
      currentStreamId = streams.isEmpty ? null : streams.first.id;
    }
    if (currentStreamId == null && streams.isNotEmpty) {
      currentStreamId = streams.first.id;
    }
  }

  Future<void> _loadCachedMessages() async {
    for (final stream in streams) {
      final local = await _local.messagesForStream(stream.id);
      _messagesByStream[stream.id] = local;
      _lastRead[stream.id] = await _local.getLastRead(stream.id);
      for (final message in local) {
        if (message.isFile) {
          final path = await _local.getFilePath(message.id);
          if (path != null) _filePaths[message.id] = path;
        }
      }
    }
  }

  Future<void> _loadLocalMessages() async {
    await _loadCachedMessages();
    notifyListeners();
  }

  Future<void> _loadAllMessages() async {
    await _loadCachedMessages();
    notifyListeners();
    if (_api == null || token == null) return;
    for (final stream in streams) {
      try {
        final remote = await _api!.messagesForStream(stream.id);
        if (remote.isEmpty) continue;
        final merged = _mergeMessages(
          _messagesByStream[stream.id] ?? const <Message>[],
          remote,
        );
        _messagesByStream[stream.id] = merged;
        for (final message in remote) {
          await _local.saveMessage(message);
        }
      } catch (_) {}
    }
    notifyListeners();
    if (isClassroom) {
      for (final stream in streams) {
        for (final message in _messagesByStream[stream.id] ?? const <Message>[]) {
          if (message.isFile &&
              !_filePaths.containsKey(message.id) &&
              !_downloadingFiles.contains(message.id)) {
            unawaited(downloadFileForMessage(message));
          }
        }
      }
    }
  }

  List<Message> _mergeMessages(List<Message> local, List<Message> remote) {
    final byId = <String, Message>{};
    for (final message in local) {
      byId[message.id] = message;
    }
    for (final message in remote) {
      byId[message.id] = message;
    }
    final result = byId.values.toList();
    result.sort(_compareMessages);
    return result;
  }

  int _compareMessages(Message a, Message b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  Future<Bootstrap?> _loadCachedBootstrap() async {
    final raw = await _local.getString('bootstrap');
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = decodeJsonObject(raw);
      return Bootstrap.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheBootstrap(Bootstrap bootstrap) =>
      _local.setString('bootstrap', encodeJson(bootstrap.toJson()));

  Future<void> _persistProfile() async {
    if (hubUrl.isNotEmpty) await _prefs.setString('hubUrl', hubUrl);
    if (token != null) await _prefs.setString('token', token!);
    if (mode != null) await _prefs.setString('mode', mode!);
    if (classId != null) await _prefs.setString('classId', classId!);
    if (grade != null) await _prefs.setInt('grade', grade!);
    if (classNo != null) await _prefs.setInt('classNo', classNo!);
    if (teacher != null) {
      await _prefs.setString('teacherId', teacher!.id);
      await _prefs.setString('teacherName', teacher!.name);
      await _prefs.setStringList('teacherClassIds', teacher!.classIds);
    }
  }

  Future<void> _clearToken() async {
    token = null;
    await _prefs.remove('token');
    await _socket?.dispose();
    _socket = null;
    connected = false;
    _api?.close();
    _api = HubApi(baseUrl: hubUrl);
  }

  void _connectSocket() {
    if (token == null || hubUrl.isEmpty) return;
    _socket?.dispose();
    final socket = HubSocket(
      baseUrl: hubUrl,
      token: token!,
      deviceId: installId ?? 'device',
      onEvent: _handleSocketEvent,
      onStatus: (bool online, {String? message}) {
        connected = online;
        connectionMessage = online ? null : (message ?? '实时连接已断开');
        notifyListeners();
      },
    );
    _socket = socket;
    socket.connect();
  }

  void _handleSocketEvent(Map<String, dynamic> event) {
    final name = asString(event['event']);
    if (name == 'hello') {
      _serverOffsetMs = asInt(event['serverTimeMs'], nowMs()) - nowMs();
      connected = true;
      connectionMessage = null;
      notifyListeners();
      unawaited(_flushOutbox());
      return;
    }
    if (name == 'message') {
      final message = _parseMessage(event['message']);
      if (message != null) {
        _handleIncoming(message, realtime: true);
      }
      return;
    }
    if (name == 'presence') {
      final devices = asMapList(event['devices']).map(PresenceInfo.fromJson).toList();
      _updatePresence(devices);
      return;
    }
    if (name == 'roster') {
      _scheduleRosterRefresh();
      return;
    }
    if (name == 'delivery') {
      final delivery = DeliveryInfo.fromJson(asMap(event['delivery']));
      _deliveries.putIfAbsent(delivery.messageId, () => <String>{}).add(delivery.recipientId);
      notifyListeners();
    }
  }

  void _updatePresence(List<PresenceInfo> devices) {
    _onlineTeachers.clear();
    _onlineClasses.clear();
    for (final device in devices) {
      if (!device.online) continue;
      if (device.role == senderTeacher) {
        _onlineTeachers.add(device.teacherId);
      } else {
        _onlineClasses.add(device.classId);
      }
    }
    notifyListeners();
  }

  void _scheduleRosterRefresh() {
    _rosterDebounce?.cancel();
    _rosterDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(refreshBootstrap());
    });
  }

  Future<void> refreshBootstrap() async {
    if (_api == null || token == null) return;
    try {
      final bootstrap = await _api!.bootstrap();
      _applyBootstrap(bootstrap);
      await _configurePeer();
      notifyListeners();
      await _loadAllMessages();
      unawaited(_flushOutbox());
    } catch (e) {
      connectionMessage = e is HubApiException ? e.message : '刷新失败';
      notifyListeners();
    }
  }

  Future<HubInfo> probeHub(String url) async {
    final normalized = HubApi.normalizeBaseUrl(url);
    final api = HubApi(baseUrl: normalized);
    try {
      final info = await api.hubInfo();
      hubUrl = normalized;
      hubInfo = info;
      await _prefs.setString('hubUrl', normalized);
      notifyListeners();
      return info;
    } finally {
      api.close();
    }
  }

  Future<List<DiscoveredHub>> discoverHubs() async {
    if (kIsWeb) return const [];
    discovering = true;
    notifyListeners();
    try {
      final result = await HubDiscovery().discover();
      discoveredHubs = result;
      return result;
    } finally {
      discovering = false;
      notifyListeners();
    }
  }

  void setHubUrl(String url) {
    hubUrl = HubApi.normalizeBaseUrl(url);
    _prefs.setString('hubUrl', hubUrl);
    notifyListeners();
  }

  Future<void> registerTeacher({
    required String name,
    required String pin,
    required String registrationCode,
    required List<String> classIds,
  }) async {
    if (hubUrl.isEmpty) throw HubApiException('请先填写 Hub 地址');
    final api = HubApi(baseUrl: hubUrl);
    try {
      final auth = await api.registerTeacher(
        name: name,
        pin: pin,
        registrationCode: registrationCode,
        classIds: classIds,
      );
      token = auth.token;
      mode = 'teacher';
      teacher = auth.teacher;
      meshKeys = auth.meshKeys;
      await _persistProfile();
      await _afterAuth(api);
    } catch (_) {
      api.close();
      rethrow;
    }
  }

  Future<void> loginTeacher({required String name, required String pin}) async {
    if (hubUrl.isEmpty) throw HubApiException('请先填写 Hub 地址');
    final api = HubApi(baseUrl: hubUrl);
    try {
      final auth = await api.loginTeacher(name: name, pin: pin);
      token = auth.token;
      mode = 'teacher';
      teacher = auth.teacher;
      meshKeys = auth.meshKeys;
      await _persistProfile();
      await _afterAuth(api);
    } catch (_) {
      api.close();
      rethrow;
    }
  }

  Future<void> _afterAuth(HubApi api) async {
    _api?.close();
    _api = api;
    api.token = token;
    final bootstrap = await api.bootstrap();
    _applyBootstrap(bootstrap);
    _setPhaseForMode();
    await _persistProfile();
    connected = false;
    notifyListeners();
    _connectSocket();
    await _configurePeer();
    await _loadAllMessages();
    unawaited(_flushOutbox());
  }

  Future<void> setupClassroom({
    required String hubUrlInput,
    required int gradeInput,
    required int classNumber,
  }) async {
    final normalized = HubApi.normalizeBaseUrl(hubUrlInput);
    if (normalized.isEmpty) throw HubApiException('请先填写 Hub 地址');
    hubUrl = normalized;
    grade = gradeInput;
    classNo = classNumber;
    classId = makeClassId(gradeInput, classNumber);
    final machine = await platform.machineName();
    deviceName = machine;
    final api = HubApi(baseUrl: hubUrl);
    try {
      final auth = await api.registerClassroom(
        installId: installId!,
        classId: classId!,
        machineName: machine,
      );
      token = auth.token;
      mode = 'classroom';
      classroom = auth.classroom;
      meshKeys = auth.meshKeys;
      await _persistProfile();
      await _afterAuth(api);
    } catch (_) {
      api.close();
      rethrow;
    }
  }

  Future<void> reconnectClassroom() async {
    if (classId == null) return;
    await setupClassroom(
      hubUrlInput: hubUrl,
      gradeInput: grade ?? 1,
      classNumber: classNo ?? 9,
    );
  }

  Future<void> retryConnection() async {
    if (token != null && hubUrl.isNotEmpty) {
      await _restoreSession();
      return;
    }
    await refreshBootstrap();
  }

  Future<void> updateTeacherClasses(List<String> classIds) async {
    if (_api == null) throw HubApiException('尚未连接服务器');
    final result = await _api!.updateClasses(classIds);
    teacher = result.teacher;
    streams = result.streams;
    meshKeys = result.meshKeys;
    if (currentStreamId != null && !streams.any((s) => s.id == currentStreamId)) {
      currentStreamId = streams.isEmpty ? null : streams.first.id;
    }
    await _prefs.setStringList('teacherClassIds', classIds);
    await _persistProfile();
    await _configurePeer();
    notifyListeners();
    await _loadAllMessages();
  }

  void setCurrentStream(String? streamId) {
    currentStreamId = streamId;
    if (streamId != null) {
      final readAt = serverNowMs;
      _lastRead[streamId] = readAt;
      unawaited(_local.setLastRead(streamId, readAt));
    }
    notifyListeners();
  }

  void markStreamRead(String streamId) {
    final readAt = serverNowMs;
    _lastRead[streamId] = readAt;
    unawaited(_local.setLastRead(streamId, readAt));
    notifyListeners();
  }

  Message _buildMessage({
    required StreamInfo stream,
    required String kind,
    String text = '',
    String title = '',
    String closeMode = closeModeManual,
    int autoCloseSec = defaultAutoCloseSeconds,
    bool sound = true,
    FileInfo? file,
  }) {
    return Message(
      id: newId(),
      streamId: stream.id,
      classId: stream.classId,
      teacherId: stream.teacherId,
      senderType: isClassroom ? senderClassroom : senderTeacher,
      senderId: myId ?? '',
      senderName: isClassroom ? '教室端' : (teacher?.name ?? ''),
      kind: kind,
      text: text,
      title: title,
      closeMode: closeMode,
      autoCloseSec: autoCloseSec,
      sound: sound,
      file: file,
      createdAt: serverNowMs,
    );
  }

  void _addMessage(Message message, {MessageSendState? state}) {
    final list = List<Message>.from(_messagesByStream[message.streamId] ?? const <Message>[]);
    final index = list.indexWhere((m) => m.id == message.id);
    if (index >= 0) {
      list[index] = message;
    } else {
      list.add(message);
    }
    list.sort(_compareMessages);
    _messagesByStream[message.streamId] = list;
    if (state != null) _sendStates[message.id] = state;
    unawaited(_local.saveMessage(message, pending: state == MessageSendState.sending));
    _touchStream(message);
  }

  void _touchStream(Message message) {
    final index = streams.indexWhere((stream) => stream.id == message.streamId);
    if (index >= 0) {
      final updated = streams[index].copyWith(
        lastMessageAt: message.createdAt,
        lastMessagePreview: message.preview,
      );
      final next = List<StreamInfo>.from(streams);
      next[index] = updated;
      streams = next;
    }
  }

  Future<bool> _sendOptimistic(Message message) async {
    _addMessage(message, state: MessageSendState.sending);
    notifyListeners();
    Future<int> direct = Future<int>.value(0);
    if (!message.isFile && _peer != null && _peer!.running) {
      direct = _peer!.send(message).catchError((Object _) => 0);
    }
    Message? saved;
    Object? hubError;
    if (_api != null) {
      try {
        saved = await _api!.sendMessage(message);
      } catch (e) {
        hubError = e;
      }
    } else {
      hubError = HubApiException('尚未连接服务器');
    }
    final directCount = await direct.timeout(
      const Duration(milliseconds: 1800),
      onTimeout: () => 0,
    );
    if (saved != null) {
      _sendStates[message.id] = MessageSendState.sent;
      _addMessage(saved, state: MessageSendState.sent);
      await _local.saveMessage(saved);
      error = null;
      notifyListeners();
      return true;
    }
    if (directCount > 0) {
      _sendStates[message.id] = MessageSendState.sent;
      await _local.saveMessage(message, pending: true);
      notifyListeners();
      return true;
    }
    _sendStates[message.id] = MessageSendState.failed;
    await _local.saveMessage(message, pending: true);
    error = hubError is HubApiException ? hubError.message : '发送失败';
    notifyListeners();
    return false;
  }

  PeerConfig? _peerConfig() {
    final id = myId;
    if (id == null || meshKeys.isEmpty) return null;
    final ids = isClassroom
        ? (classId == null ? <String>[] : <String>[classId!])
        : (teacher?.classIds ?? <String>[]);
    if (ids.isEmpty) return null;
    return PeerConfig(
      deviceId: installId ?? id,
      role: isClassroom ? senderClassroom : senderTeacher,
      name: isClassroom ? deviceName : (teacher?.name ?? ''),
      classIds: ids,
      teacherId: teacher?.id ?? '',
      meshKeys: meshKeys,
    );
  }

  Future<void> _configurePeer() async {
    if (kIsWeb) return;
    final config = _peerConfig();
    if (config == null) {
      await _peer?.stop();
      _peer = null;
      return;
    }
    if (_peer == null) {
      _peer = PeerService(
        onMessage: (Message message) async {
          if (_disposed) return;
          await _handleIncoming(message, realtime: true);
        },
        onPresence: (List<PeerInfo> peers) {
          if (_disposed) return;
          _peerOnlineTeachers.clear();
          _peerOnlineClasses.clear();
          for (final peer in peers) {
            if (peer.isTeacher) {
              if (peer.teacherId.isNotEmpty) _peerOnlineTeachers.add(peer.teacherId);
            } else {
              _peerOnlineClasses.addAll(peer.classIds);
            }
          }
          notifyListeners();
        },
      );
      await _peer!.start(config);
    } else {
      await _peer!.update(config);
    }
  }

  Future<void> _flushOutbox() async {
    if (_flushingOutbox || _api == null || _disposed) return;
    _flushingOutbox = true;
    try {
      final pending = await _local.pendingMessages();
      for (final message in pending) {
        if (_disposed) break;
        try {
          final saved = await _api!.sendMessage(message);
          _sendStates[message.id] = MessageSendState.sent;
          _addMessage(saved, state: MessageSendState.sent);
          await _local.saveMessage(saved);
        } catch (_) {}
      }
      if (pending.isNotEmpty) notifyListeners();
    } finally {
      _flushingOutbox = false;
    }
  }

  Future<bool> sendChat(String text) async {
    final stream = currentStream;
    if (stream == null) return false;
    final value = text.trim();
    if (value.isEmpty) return false;
    final message = _buildMessage(stream: stream, kind: kindChat, text: value);
    return _sendOptimistic(message);
  }

  Future<void> sendNotice({
    required String title,
    required String text,
    required String closeMode,
    required int autoCloseSec,
    required bool sound,
    required bool allClasses,
  }) async {
    final targets = allClasses ? streams : [?currentStream];
    if (targets.isEmpty) {
      error = '未选择班级';
      notifyListeners();
      return;
    }
    if (!isTeacher) return;
    for (final stream in targets) {
      final message = _buildMessage(
        stream: stream,
        kind: kindNotice,
        title: title.trim(),
        text: text.trim(),
        closeMode: closeMode,
        autoCloseSec: autoCloseSec,
        sound: sound,
      );
      await _sendOptimistic(message);
    }
  }

  Future<void> sendFiles({
    required List<PlatformFile> files,
    required bool allClasses,
  }) async {
    if (!isTeacher || files.isEmpty) return;
    final targets = allClasses ? streams : [?currentStream];
    if (targets.isEmpty) {
      error = '未选择班级';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
      final file = files[fileIndex];
      busyText = '正在上传 ${fileIndex + 1}/${files.length}：${file.name}';
      notifyListeners();
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          throw HubApiException('文件为空：${file.name}');
        }
        final sha = sha256Hex(bytes);
        final mimeType = lookupMimeType(file.name) ?? 'application/octet-stream';
        final ticket = await _api!.registerFile(
          name: file.name,
          size: bytes.length,
          sha256: sha,
          mime: mimeType,
        );
        if (ticket.uploadRequired) {
          await _api!.uploadFileBytes(ticket.file.id, bytes);
        }
        for (final stream in targets) {
          final message = _buildMessage(
            stream: stream,
            kind: kindFile,
            text: '',
            file: ticket.file,
          );
          final localPath = file.path;
          if (localPath != null && localPath.isNotEmpty) {
            _filePaths[message.id] = localPath;
            unawaited(_local.setFilePath(message.id, localPath));
          }
          await _sendOptimistic(message);
        }
      } catch (e) {
        error = e is HubApiException ? e.message : '文件发送失败';
      }
    }
    busy = false;
    busyText = null;
    notifyListeners();
  }

  Future<void> _handleIncoming(Message message, {required bool realtime}) async {
    final list = _messagesByStream[message.streamId];
    final existing = list?.where((m) => m.id == message.id).toList() ?? const <Message>[];
    if (existing.isNotEmpty) {
      final old = existing.first;
      if (old.seq != message.seq) {
        _addMessage(message, state: _sendStates[message.id] ?? MessageSendState.sent);
        notifyListeners();
      }
      return;
    }
    _addMessage(message, state: _isMine(message) ? MessageSendState.sent : null);
    if (message.streamId == currentStreamId) {
      final readAt = serverNowMs;
      _lastRead[message.streamId] = readAt;
      unawaited(_local.setLastRead(message.streamId, readAt));
    }
    notifyListeners();
    if (!_isMine(message)) {
      _ack(message);
    }
    if (isClassroom && message.isNotice && message.fromTeacher) {
      final age = serverNowMs - message.createdAt;
      if (realtime && age >= 0 && age < noticeFreshnessMs) {
        _enqueueNotice(message);
      }
    }
    if (isClassroom && message.isFile) {
      unawaited(downloadFileForMessage(message));
    }
    _scheduleRosterRefreshIfNeeded(message);
  }

  void _scheduleRosterRefreshIfNeeded(Message message) {
    if (classTeachers.any((t) => t.id == message.teacherId)) return;
    if (isClassroom) {
      final info = parseClassId(message.classId);
      if (info == null) return;
      final stream = StreamInfo(
        id: message.streamId,
        classId: message.classId,
        teacherId: message.teacherId,
        teacherName: message.senderName.isEmpty ? '老师' : message.senderName,
        className: info.title,
      );
      if (!streams.any((s) => s.id == stream.id)) {
        streams = [...streams, stream];
      }
    }
  }

  Future<void> _ack(Message message) async {
    if (_acksSent.contains(message.id)) return;
    _acksSent.add(message.id);
    try {
      if (_socket != null && connected) {
        _socket!.sendAck(message.id);
      } else {
        await _api?.ack(message.id);
      }
    } catch (_) {}
  }

  Future<void> downloadFileForMessage(Message message) async {
    if (!isClassroom || message.file == null) return;
    if (_filePaths.containsKey(message.id) || _downloadingFiles.contains(message.id)) return;
    if (_api == null) return;
    _downloadingFiles.add(message.id);
    notifyListeners();
    try {
      final bytes = await _api!.downloadFile(message.file!.id);
      final stream = streams.where((s) => s.id == message.streamId).toList();
      final teacherName = stream.isNotEmpty ? stream.first.teacherName : '老师';
      final saved = await platform.saveReceivedFile(
        bytes: bytes,
        fileName: message.file!.name,
        className: currentClassTitle,
        teacherName: teacherName,
      );
      _filePaths[message.id] = saved.displayName;
      await _local.setFilePath(message.id, saved.displayName);
    } catch (e) {
      error = e is HubApiException ? e.message : '文件接收失败';
    } finally {
      _downloadingFiles.remove(message.id);
      notifyListeners();
    }
  }

  Future<void> openMessageFile(Message message) async {
    final path = _filePaths[message.id];
    if (path == null || path.isEmpty) return;
    await platform.openFile(path);
  }

  Future<void> revealMessageFile(Message message) async {
    final path = _filePaths[message.id];
    if (path == null || path.isEmpty) return;
    await platform.revealFile(path);
  }

  void _enqueueNotice(Message message) {
    if (activeNotice?.id == message.id) return;
    if (_noticeQueue.any((m) => m.id == message.id)) return;
    _noticeQueue.add(message);
    if (activeNotice == null) {
      _showNextNotice();
    } else {
      notifyListeners();
    }
  }

  void _showNextNotice() {
    _noticeTimer?.cancel();
    if (_noticeQueue.isEmpty) {
      activeNotice = null;
      platform.setNoticeFullscreen(false);
      platform.keepAwake(false);
      notifyListeners();
      return;
    }
    final next = _noticeQueue.removeAt(0);
    activeNotice = next;
    platform.setNoticeFullscreen(true);
    platform.keepAwake(true);
    if (next.sound) _playSound();
    if (next.closeMode == closeModeAuto) {
      final seconds = next.autoCloseSec.clamp(1, maxAutoCloseSeconds);
      _noticeTimer = Timer(Duration(seconds: seconds), () {
        dismissNotice();
      });
    }
    notifyListeners();
  }

  void dismissNotice() {
    _noticeTimer?.cancel();
    activeNotice = null;
    _showNextNotice();
  }

  void previewNotice(Message message) {
    if (!isClassroom) return;
    _enqueueNotice(message);
  }

  Future<void> _playSound() async {
    if (!soundEnabled) return;
    try {
      _player ??= AudioPlayer();
      await _player!.play(AssetSource('notice.wav'));
    } catch (_) {}
  }

  Future<void> setSoundEnabled(bool enabled) async {
    await _prefs.setBool('soundEnabled', enabled);
    notifyListeners();
  }

  bool get soundEnabled => _prefs.getBool('soundEnabled') ?? true;

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  String? get debugTeacherClassIds =>
      _prefs.getStringList('teacherClassIds')?.join(',');

  Future<void> resetEverything() async {
    await _socket?.dispose();
    _socket = null;
    await _local.clearAll();
    await _prefs.clear();
    mode = null;
    token = null;
    teacher = null;
    classroom = null;
    classId = null;
    grade = null;
    classNo = null;
    streams = const [];
    _messagesByStream.clear();
    _lastRead.clear();
    _filePaths.clear();
    currentStreamId = null;
    activeNotice = null;
    _noticeQueue.clear();
    hubUrl = kIsWeb ? Uri.base.origin : '';
    phase = AppPhase.onboarding;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _noticeTimer?.cancel();
    _rosterDebounce?.cancel();
    _socket?.dispose();
    _peer?.stop();
    _api?.close();
    _player?.dispose();
    _local.close();
    super.dispose();
  }
}

Message? _parseMessage(Object? raw) {
  final map = asMap(raw);
  if (map.isEmpty) return null;
  try {
    final message = Message.fromJson(map);
    return message.id.isEmpty ? null : message;
  } catch (_) {
    return null;
  }
}
