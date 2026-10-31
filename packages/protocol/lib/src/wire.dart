import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

final Uuid _uuid = const Uuid();
final Random _random = Random.secure();

String newId() {
  try {
    return _uuid.v7();
  } catch (_) {
    return _uuid.v4();
  }
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

String randomToken({int bytes = 32}) {
  final data = Uint8List.fromList(List<int>.generate(bytes, (_) => _random.nextInt(256)));
  return base64UrlEncode(data).replaceAll('=', '');
}

String randomCode({int digits = 6}) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits; i++) {
    buffer.write(_random.nextInt(10));
  }
  return buffer.toString();
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String sha256OfString(String value) => sha256Hex(utf8.encode(value));

String hmacSha256Hex(String key, String data) {
  final hmac = Hmac(sha256, utf8.encode(key));
  return hmac.convert(utf8.encode(data)).toString();
}

bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
}

String canonicalJson(Object? value) {
  Object? normalize(Object? input) {
    if (input is Map) {
      final map = <String, Object?>{};
      final keys = input.keys.map((e) => e.toString()).toList()..sort();
      for (final key in keys) {
        map[key] = normalize(input[key]);
      }
      return map;
    }
    if (input is List) {
      return input.map(normalize).toList(growable: false);
    }
    return input;
  }

  return jsonEncode(normalize(value));
}

String signMessage(Message message, String meshKey) =>
    hmacSha256Hex(meshKey, canonicalJson(message.toJson()));

bool verifyMessage(Message message, String meshKey, String signature) =>
    constantTimeEquals(signMessage(message, meshKey), signature);

Map<String, dynamic> peerEnvelope(Message message, String meshKey) => {
      'message': message.toJson(),
      'sig': signMessage(message, meshKey),
    };

Message? decodePeerEnvelope(Object? raw, String meshKey) {
  final map = asMap(raw);
  if (map.isEmpty) return null;
  final message = Message.fromJson(asMap(map['message']));
  if (message.id.isEmpty || message.streamId.isEmpty) return null;
  if (!verifyMessage(message, meshKey, asString(map['sig']))) return null;
  return message;
}

String peerHandshakePayload({
  required String deviceId,
  required String role,
  required String classId,
  required String nonce,
  required int timestamp,
}) =>
    canonicalJson({
      'deviceId': deviceId,
      'role': role,
      'classId': classId,
      'nonce': nonce,
      'ts': timestamp,
    });

String signPeerHandshake({
  required String meshKey,
  required String deviceId,
  required String role,
  required String classId,
  required String nonce,
  required int timestamp,
}) =>
    hmacSha256Hex(
      meshKey,
      peerHandshakePayload(
        deviceId: deviceId,
        role: role,
        classId: classId,
        nonce: nonce,
        timestamp: timestamp,
      ),
    );

bool verifyPeerHandshake({
  required String meshKey,
  required String deviceId,
  required String role,
  required String classId,
  required String nonce,
  required int timestamp,
  required String signature,
  int maxSkewMs = 120000,
}) {
  if ((nowMs() - timestamp).abs() > maxSkewMs) return false;
  final expected = signPeerHandshake(
    meshKey: meshKey,
    deviceId: deviceId,
    role: role,
    classId: classId,
    nonce: nonce,
    timestamp: timestamp,
  );
  return constantTimeEquals(expected, signature);
}

Uint8List pbkdf2HmacSha256(
  List<int> password,
  List<int> salt, {
  int iterations = 60000,
  int length = 32,
}) {
  final prf = Hmac(sha256, password);
  const digestLength = 32;
  final blockCount = (length + digestLength - 1) ~/ digestLength;
  final output = BytesBuilder(copy: false);
  for (var block = 1; block <= blockCount; block++) {
    final blockBytes = Uint8List(4);
    blockBytes[0] = (block >> 24) & 0xff;
    blockBytes[1] = (block >> 16) & 0xff;
    blockBytes[2] = (block >> 8) & 0xff;
    blockBytes[3] = block & 0xff;
    var u = Uint8List.fromList(prf.convert([...salt, ...blockBytes]).bytes);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(prf.convert(u).bytes);
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    output.add(t);
  }
  return Uint8List.sublistView(output.toBytes(), 0, length);
}

class PinHash {
  const PinHash({required this.salt, required this.hash, this.iterations = 60000});

  final String salt;
  final String hash;
  final int iterations;

  static PinHash create(String pin, {int iterations = 60000}) {
    final saltBytes = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    final hashBytes = pbkdf2HmacSha256(
      utf8.encode(pin),
      saltBytes,
      iterations: iterations,
    );
    return PinHash(
      salt: base64Encode(saltBytes),
      hash: base64Encode(hashBytes),
      iterations: iterations,
    );
  }

  bool verify(String pin) {
    final saltBytes = base64Decode(salt);
    final expected = pbkdf2HmacSha256(
      utf8.encode(pin),
      saltBytes,
      iterations: iterations,
    );
    return constantTimeEquals(base64Encode(expected), hash);
  }
}

bool verifyPin({
  required String pin,
  required String salt,
  required String hash,
  int iterations = 60000,
}) {
  final computed = pbkdf2HmacSha256(
    utf8.encode(pin),
    base64Decode(salt),
    iterations: iterations,
  );
  return constantTimeEquals(base64Encode(computed), hash);
}

String encodeJson(Object? value) => jsonEncode(value);

Map<String, dynamic> decodeJsonObject(String raw) {
  final decoded = jsonDecode(raw);
  return asMap(decoded);
}
