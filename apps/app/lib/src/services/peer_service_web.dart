import 'peer_info.dart';
import 'package:school_link_protocol/protocol.dart';

class PeerService {
  PeerService({
    required this.onMessage,
    required this.onPresence,
  });

  final PeerMessageHandler onMessage;
  final PeerPresenceHandler onPresence;

  bool get running => false;
  String? get error => null;
  List<PeerInfo> get peers => const [];

  Future<void> start(PeerConfig config) async {}

  Future<void> update(PeerConfig config) async {}

  Future<void> stop() async {}

  Future<int> send(Message message) async => 0;
}
