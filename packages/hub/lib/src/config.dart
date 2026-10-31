import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:school_link_protocol/protocol.dart';

class HubConfig {
  HubConfig({
    required this.id,
    required this.name,
    required this.adminPinSalt,
    required this.adminPinHash,
    required this.registrationCode,
    required this.createdAt,
    this.registrationRequired = true,
    this.maxFileBytes = 2 * 1024 * 1024 * 1024,
    this.retentionDays = 90,
  });

  final String id;
  String name;
  String adminPinSalt;
  String adminPinHash;
  String registrationCode;
  final int createdAt;
  bool registrationRequired;
  int maxFileBytes;
  int retentionDays;

  factory HubConfig.createDefault({String name = '校联服务器'}) {
    const defaultPin = '246810';
    final pinHash = PinHash.create(defaultPin);
    return HubConfig(
      id: newId(),
      name: name,
      adminPinSalt: pinHash.salt,
      adminPinHash: pinHash.hash,
      registrationCode: 'SCHOOL26',
      createdAt: nowMs(),
    );
  }

  factory HubConfig.fromJson(Map<String, dynamic> json) => HubConfig(
        id: asString(json['id'], newId()),
        name: asString(json['name'], '校联服务器'),
        adminPinSalt: asString(json['adminPinSalt']),
        adminPinHash: asString(json['adminPinHash']),
        registrationCode: asString(json['registrationCode'], 'SCHOOL26'),
        createdAt: asInt(json['createdAt'], nowMs()),
        registrationRequired: asBool(json['registrationRequired'], true),
        maxFileBytes: asInt(json['maxFileBytes'], 2 * 1024 * 1024 * 1024),
        retentionDays: asInt(json['retentionDays'], 90),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'adminPinSalt': adminPinSalt,
        'adminPinHash': adminPinHash,
        'registrationCode': registrationCode,
        'createdAt': createdAt,
        'registrationRequired': registrationRequired,
        'maxFileBytes': maxFileBytes,
        'retentionDays': retentionDays,
      };

  bool verifyAdminPin(String pin) => verifyPin(
        pin: pin,
        salt: adminPinSalt,
        hash: adminPinHash,
      );

  void setAdminPin(String pin) {
    final hash = PinHash.create(pin);
    adminPinSalt = hash.salt;
    adminPinHash = hash.hash;
  }
}

class HubConfigFile {
  HubConfigFile._();

  static File fileFor(String dataDir) =>
      File(p.join(dataDir, 'hub_config.json'));

  static Future<HubConfig> loadOrCreate(String dataDir, {String? name}) async {
    await Directory(dataDir).create(recursive: true);
    final file = fileFor(dataDir);
    if (await file.exists()) {
      final raw = await file.readAsString();
      final json = decodeJsonObject(raw);
      if (json.isNotEmpty) return HubConfig.fromJson(json);
    }
    final config = HubConfig.createDefault(name: name ?? '校联服务器');
    await save(dataDir, config);
    return config;
  }

  static Future<void> save(String dataDir, HubConfig config) async {
    await Directory(dataDir).create(recursive: true);
    final file = fileFor(dataDir);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(const JsonEncoder.withIndent('  ').convert(config.toJson()));
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
