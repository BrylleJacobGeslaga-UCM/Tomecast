import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal ZIP reader for EPUB files (an EPUB is a ZIP).
/// Reads the file list, small files into memory, and streams big files
/// (audio) straight to disk without loading them into memory.
class EpubZip {
  EpubZip._(this.path, this.entries);

  final String path;
  final Map<String, ZipEntry> entries;

  static EpubZip open(String path) {
    final raf = File(path).openSync();
    try {
      final length = raf.lengthSync();

      // 1. Find the "end of central directory" record near the end.
      final tailSize = length < 65557 ? length : 65557;
      raf.setPositionSync(length - tailSize);
      final tail = raf.readSync(tailSize);
      final tailData = ByteData.sublistView(tail);
      var eocd = -1;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (tailData.getUint32(i, Endian.little) == 0x06054b50) {
          eocd = i;
          break;
        }
      }
      if (eocd < 0) throw const FormatException('Not a ZIP/EPUB file');

      final count = tailData.getUint16(eocd + 10, Endian.little);
      final dirSize = tailData.getUint32(eocd + 12, Endian.little);
      final dirOffset = tailData.getUint32(eocd + 16, Endian.little);

      // 2. Read the central directory: one record per file.
      raf.setPositionSync(dirOffset);
      final dir = raf.readSync(dirSize);
      final d = ByteData.sublistView(dir);
      final entries = <String, ZipEntry>{};
      var p = 0;
      for (var i = 0; i < count && p + 46 <= dir.length; i++) {
        if (d.getUint32(p, Endian.little) != 0x02014b50) break;
        final method = d.getUint16(p + 10, Endian.little);
        final compressed = d.getUint32(p + 20, Endian.little);
        final uncompressed = d.getUint32(p + 24, Endian.little);
        final nameLen = d.getUint16(p + 28, Endian.little);
        final extraLen = d.getUint16(p + 30, Endian.little);
        final commentLen = d.getUint16(p + 32, Endian.little);
        final localOffset = d.getUint32(p + 42, Endian.little);
        final name = String.fromCharCodes(dir, p + 46, p + 46 + nameLen);
        entries[name] = ZipEntry(
          name: name,
          method: method,
          compressedSize: compressed,
          size: uncompressed,
          localHeaderOffset: localOffset,
        );
        p += 46 + nameLen + extraLen + commentLen;
      }
      return EpubZip._(path, entries);
    } finally {
      raf.closeSync();
    }
  }

  bool contains(String name) => entries.containsKey(name);

  /// Where the file's data starts (after its local header).
  int _dataStart(RandomAccessFile raf, ZipEntry e) {
    raf.setPositionSync(e.localHeaderOffset);
    final h = ByteData.sublistView(raf.readSync(30));
    if (h.getUint32(0, Endian.little) != 0x04034b50) {
      throw FormatException('Broken ZIP entry: ${e.name}');
    }
    final nameLen = h.getUint16(26, Endian.little);
    final extraLen = h.getUint16(28, Endian.little);
    return e.localHeaderOffset + 30 + nameLen + extraLen;
  }

  /// Reads a small file (XML, XHTML) into memory.
  Uint8List read(String name) {
    final e = entries[name];
    if (e == null) throw FormatException('Missing in EPUB: $name');
    final raf = File(path).openSync();
    try {
      raf.setPositionSync(_dataStart(raf, e));
      final raw = raf.readSync(e.compressedSize);
      return _decompress(e, raw);
    } finally {
      raf.closeSync();
    }
  }

  String readText(String name) => _utf8(read(name));

  static String _utf8(Uint8List bytes) {
    // Skip a UTF-8 BOM if present.
    final start = (bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF)
        ? 3
        : 0;
    return const Utf8Decoder(allowMalformed: true).convert(bytes, start);
  }

  static Uint8List _decompress(ZipEntry e, Uint8List raw) {
    switch (e.method) {
      case 0: // stored
        return raw;
      case 8: // deflate
        return Uint8List.fromList(ZLibCodec(raw: true).decode(raw));
      default:
        throw FormatException('Unsupported compression in ${e.name}');
    }
  }

  /// Copies a (possibly huge) file out of the EPUB to [outPath].
  Future<void> extractTo(String name, String outPath) async {
    final e = entries[name];
    if (e == null) throw FormatException('Missing in EPUB: $name');

    final raf = File(path).openSync();
    final int start;
    try {
      start = _dataStart(raf, e);
    } finally {
      raf.closeSync();
    }

    Stream<List<int>> data = File(path).openRead(start, start + e.compressedSize);
    if (e.method == 8) {
      data = data.transform(ZLibDecoder(raw: true));
    } else if (e.method != 0) {
      throw FormatException('Unsupported compression in ${e.name}');
    }

    final tmp = File('$outPath.part');
    await tmp.parent.create(recursive: true);
    final sink = tmp.openWrite();
    await sink.addStream(data);
    await sink.close();
    await tmp.rename(outPath); // only "done" once fully written
  }
}

class ZipEntry {
  final String name;
  final int method;
  final int compressedSize;
  final int size;
  final int localHeaderOffset;

  const ZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.size,
    required this.localHeaderOffset,
  });
}
