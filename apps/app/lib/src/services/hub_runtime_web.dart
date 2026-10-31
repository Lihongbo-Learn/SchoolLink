import 'package:flutter/foundation.dart';

final HubRuntime hubRuntime = HubRuntime();

class HubRuntime extends ChangeNotifier {
  bool get supported => false;

  bool get running => false;

  bool get starting => false;

  String? get error => null;

  List<String> get urls => const [];

  String get localUrl => '';

  String? get dataDir => null;

  String? get webRoot => null;

  bool get hasWebBuild => false;

  Future<void> start() async {}

  Future<void> stop() async {}
}
