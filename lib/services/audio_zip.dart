import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

typedef ZipAudio = ({
  String path,
  String name,
  String extension,
  String hash,
  int bytes,
  String? artist,
  String? title,
  int? seconds,
});

typedef ZipAudioBatch = ({List<ZipAudio> tracks, int duplicates});

const localAudioExtensions = ['mp3', 'm4a', 'aac', 'wav', 'flac', 'aiff', 'aif', 'caf', 'alac'];
const transferManifest = 'echoes-transfer.json';

/// Decompresses to a temporary directory on a worker isolate. Archive paths
/// are used as labels only, never as destination paths.
Future<ZipAudioBatch> unpackAudioZip((String, String) paths) async {
  final (zipPath, stagingPath) = paths;
  final input = InputFileStream(zipPath);
  try {
    final directory = ZipDirectory()..read(input);
    if (directory.filePosition < 0 ||
        directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0 ||
        directory.totalCentralDirectoryEntries != directory.fileHeaders.length) {
      throw const FormatException('Invalid ZIP directory');
    }
    final entries = directory.fileHeaders.where((entry) => ((entry.externalFileAttributes >> 16) & 0xf000) != 0xa000);
    final metadataFile = entries.where((entry) => entry.file?.filename == transferManifest).firstOrNull?.file;
    final metadata = _metadata(metadataFile);
    final tracks = <ZipAudio>[];
    final hashes = <String>{};
    var duplicates = 0;
    for (final entry in entries) {
      final audio = entry.file;
      if (audio == null) continue;
      final filename = audio.filename.replaceAll(r'\', '/');
      final segments = filename.split('/');
      if (filename.startsWith('/') ||
          filename.contains('\u0000') ||
          segments.contains('..') ||
          segments.first == '__MACOSX' ||
          segments.last.startsWith('.')) {
        continue;
      }
      final name = segments.last;
      final dot = name.lastIndexOf('.');
      if (dot < 1) continue;
      final extension = name.substring(dot + 1).toLowerCase();
      if (!localAudioExtensions.contains(extension)) continue;
      if ((audio.flags & 1) != 0 || audio.uncompressedSize <= 0) {
        throw const FormatException('Encrypted or empty audio in ZIP');
      }
      final staged = File('$stagingPath/${tracks.length}.$extension');
      final output = OutputFileStream(staged.path);
      try {
        audio.decompress(output);
        if (output.length != audio.uncompressedSize) throw const FormatException('Incomplete ZIP entry');
      } finally {
        output.closeSync();
      }
      var crc = 0;
      final digest = await sha256
          .bind(
            staged.openRead().map((chunk) {
              crc = getCrc32(chunk, crc);
              return chunk;
            }),
          )
          .single;
      if (crc != entry.crc32) throw const FormatException('Damaged ZIP entry');
      final hash = digest.toString();
      if (!hashes.add(hash)) {
        duplicates++;
        staged.deleteSync();
        continue;
      }
      final tags = metadata[filename];
      final duration = tags?['duration'];
      tracks.add((
        path: staged.path,
        name: name,
        extension: extension,
        hash: hash,
        bytes: output.length,
        artist: _text(tags?['artist']),
        title: _text(tags?['title']),
        seconds: duration is num && duration.isFinite ? duration.round().clamp(0, 86400) : null,
      ));
    }
    return (tracks: tracks, duplicates: duplicates);
  } finally {
    input.closeSync();
  }
}

Map<String, Map<String, dynamic>> _metadata(ZipFile? entry) {
  if (entry == null || entry.uncompressedSize <= 0 || entry.uncompressedSize > 1024 * 1024 || (entry.flags & 1) != 0) {
    return {};
  }
  try {
    final json = jsonDecode(utf8.decode(entry.getStream().toUint8List()));
    if (json is! Map || json['format'] != 'echoes-offline-tracks' || json['version'] != 1) return {};
    final items = json['tracks'];
    if (items is! List) return {};
    return {
      for (final item in items)
        if (item is Map<String, dynamic> && item['file'] is String) item['file'] as String: item,
    };
  } on FormatException {
    return {};
  }
}

String? _text(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return String.fromCharCodes(value.trim().runes.take(400));
}
