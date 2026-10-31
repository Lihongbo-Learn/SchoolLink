import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:school_link_protocol/protocol.dart';

import 'errors.dart';

class FileStore {
  FileStore(this.rootDir);

  final String rootDir;

  File _blobFile(String fileId) => File(p.join(rootDir, 'files', '$fileId.bin'));

  File _partFile(String fileId) => File(p.join(rootDir, 'files', '$fileId.part'));

  Future<void> init() async {
    await Directory(p.join(rootDir, 'files')).create(recursive: true);
  }

  Future<FileInfo> writeStream({
    required String fileId,
    required String name,
    required String mime,
    required Stream<List<int>> stream,
    required int expectedSize,
    required String expectedSha256,
    int? expiresAt,
  }) async {
    final part = _partFile(fileId);
    await part.parent.create(recursive: true);
    final sink = part.openWrite();
    final digestOutput = AccumulatorSink<Digest>();
    final digestSink = sha256.startChunkedConversion(digestOutput);
    var total = 0;
    try {
      await for (final chunk in stream) {
        total += chunk.length;
        sink.add(chunk);
        digestSink.add(chunk);
        if (total > expectedSize) {
          throw HubException('文件大小超过声明值', statusCode: 413);
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (await part.exists()) await part.delete();
      rethrow;
    }
    digestSink.close();
    final digest = digestOutput.events.single.toString();
    if (total != expectedSize) {
      if (await part.exists()) await part.delete();
      throw HubException('文件大小不一致：$total/$expectedSize');
    }
    if (expectedSha256.isNotEmpty && digest != expectedSha256) {
      if (await part.exists()) await part.delete();
      throw HubException('文件校验失败');
    }
    final target = _blobFile(fileId);
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
    return FileInfo(
      id: fileId,
      name: sanitizeFileName(name),
      size: total,
      sha256: digest,
      mime: mime.isEmpty ? 'application/octet-stream' : mime,
      expiresAt: expiresAt,
    );
  }

  File? fileFor(String fileId) {
    final file = _blobFile(fileId);
    return file.existsSync() ? file : null;
  }

  Future<void> deleteBlob(String fileId) async {
    final file = _blobFile(fileId);
    if (await file.exists()) await file.delete();
    final part = _partFile(fileId);
    if (await part.exists()) await part.delete();
  }

  Future<int> totalBytes() async {
    final dir = Directory(p.join(rootDir, 'files'));
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}
