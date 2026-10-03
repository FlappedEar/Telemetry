// Port of the ZIP layer of VBOOverlay native/src/telemetry/RczParser.cpp
// (FET-16): reads members of a RaceChrono RCZ archive without extracting
// anything to the filesystem.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../operation.dart';

/// An RCZ archive or session is malformed or unsupported.
final class RczFormatError implements Exception {
  RczFormatError(String message) : message = 'RCZ: $message';
  final String message;
  @override
  String toString() => message;
}

Never _fail(String message) => throw RczFormatError(message);

/// Archive limits, as in the C++ reader.
const int maximumRczArchiveBytes = 128 * 1024 * 1024;
const int maximumRczMemberBytes = 32 * 1024 * 1024;
const int maximumRczExpandedBytes = 256 * 1024 * 1024;
const int maximumRczMembers = 1024;

const int _chunkBytes = 64 * 1024;

/// One member as described by the central directory.
final class RczMember {
  RczMember._(
    this.name,
    this.method,
    this.compressedBytes,
    this.expandedBytes,
    this.crc32,
    this.dataOffset,
  );
  final String name;

  /// 0 stored, 8 deflated.
  final int method;
  final int compressedBytes;
  final int expandedBytes;
  final int crc32;
  final int dataOffset;
}

/// A flat ZIP32 archive with stored and deflated members only.
///
/// The central directory and every local header are validated before any
/// member data is read: paths, duplicate names, offsets, overlapping members,
/// sizes and flags. Reading a member checks its size and CRC-32, and caps
/// inflation at the declared size, so a dishonest header cannot expand
/// beyond it. Cooperatively cancellable. Call [close] when done.
final class RczArchive {
  RczArchive._(this._file, this._cancelled, this.members);

  final RandomAccessFile _file;
  final CancellationCheck? _cancelled;

  /// Members by name, in code-unit order of their names.
  final SplayTreeMap<String, RczMember> members;

  /// Opens and validates the archive at [path].
  static RczArchive open(String path, {CancellationCheck? cancelled}) {
    throwIfCancelled(cancelled);
    final RandomAccessFile file;
    try {
      file = File(path).openSync();
    } on FileSystemException catch (error) {
      _fail(error.osError?.message ?? error.message);
    }
    try {
      final members = _readDirectory(file, cancelled);
      return RczArchive._(file, cancelled, members);
    } catch (_) {
      file.closeSync();
      rethrow;
    }
  }

  void close() => _file.closeSync();

  /// The expanded bytes of [name], at most [limit] bytes.
  Uint8List data(String name, {int limit = maximumRczMemberBytes}) {
    final entry = members[name] ?? _fail('Missing $name.');
    if (entry.expandedBytes > limit) _fail('$name exceeds its size limit.');
    final result = BytesBuilder(copy: false);
    var checksum = _Crc32();
    var remaining = entry.compressedBytes;
    var position = entry.dataOffset;
    final inflater = entry.method == 8 ? RawZLibFilter.inflateFilter(raw: true) : null;
    void append(List<int> chunk) {
      if (result.length + chunk.length > entry.expandedBytes) {
        _fail('Decompression exceeded declared size.');
      }
      result.add(chunk);
      checksum = checksum.update(chunk);
    }

    void drain({required bool end}) {
      while (true) {
        throwIfCancelled(_cancelled);
        final List<int>? chunk;
        try {
          chunk = inflater!.processed(flush: end, end: end);
        } on FormatException {
          _fail('Corrupt compressed member.');
        }
        if (chunk == null) return;
        if (chunk.isNotEmpty) append(chunk);
      }
    }

    while (remaining > 0) {
      throwIfCancelled(_cancelled);
      final count = remaining < _chunkBytes ? remaining : _chunkBytes;
      final input = _readAt(_file, position, count);
      position += count;
      remaining -= count;
      if (inflater == null) {
        append(input);
      } else {
        try {
          inflater.process(input, 0, input.length);
        } on FormatException {
          _fail('Corrupt compressed member.');
        }
        drain(end: false);
      }
    }
    if (inflater != null) drain(end: true);
    throwIfCancelled(_cancelled);
    if (result.length != entry.expandedBytes || checksum.value != entry.crc32) {
      _fail('Size or checksum mismatch in $name.');
    }
    return result.takeBytes();
  }
}

SplayTreeMap<String, RczMember> _readDirectory(
  RandomAccessFile file,
  CancellationCheck? cancelled,
) {
  final size = file.lengthSync();
  if (size < 22 || size > maximumRczArchiveBytes) {
    _fail('Archive size is unsupported.');
  }
  final tailAt = size - 65557 > 0 ? size - 65557 : 0;
  final tail = _View(_readAt(file, tailAt, size - tailAt));
  var end = -1;
  for (var i = tail.length - 22; i >= 0; --i) {
    if (tail.u32(i) == 0x06054b50 && i + 22 + tail.u16(i + 20) == tail.length) {
      end = i;
      break;
    }
  }
  if (end < 0) _fail('Missing ZIP directory.');
  final count = tail.u16(end + 10);
  final directorySize = tail.u32(end + 12), directoryAt = tail.u32(end + 16);
  if (tail.u16(end + 4) != 0 ||
      tail.u16(end + 6) != 0 ||
      count != tail.u16(end + 8) ||
      count < 1 ||
      count > maximumRczMembers ||
      directorySize > 1024 * 1024 ||
      directoryAt + directorySize != tailAt + end) {
    _fail('Unsupported ZIP64, split archive or directory limits.');
  }
  final directory = _View(_readAt(file, directoryAt, directorySize));
  final members = SplayTreeMap<String, RczMember>();
  final spans = <(int, int)>[];
  var at = 0, expandedTotal = 0;
  for (var index = 0; index < count; ++index) {
    throwIfCancelled(cancelled);
    if (at + 46 > directory.length || directory.u32(at) != 0x02014b50) {
      _fail('Invalid ZIP directory entry.');
    }
    final version = directory.u16(at + 6);
    final flags = directory.u16(at + 8), method = directory.u16(at + 10);
    final nameSize = directory.u16(at + 28);
    final extra = directory.u16(at + 30), comment = directory.u16(at + 32);
    if (version > 20 ||
        (flags & ~0x080e) != 0 ||
        (method != 0 && method != 8) ||
        directory.u16(at + 34) != 0 ||
        nameSize == 0 ||
        nameSize > 512 ||
        at + 46 + nameSize + extra + comment > directory.length) {
      _fail('Unsupported or malformed ZIP member.');
    }
    final rawName = directory.bytes.sublist(at + 46, at + 46 + nameSize);
    final name = _safeName(rawName);
    final attributes = directory.u32(at + 38);
    if (((attributes >> 16) & 0xf000) == 0xa000) {
      _fail('Symbolic links are unsupported.');
    }
    final compressed = directory.u32(at + 20);
    final expanded = directory.u32(at + 24);
    final crc = directory.u32(at + 16);
    if (members.containsKey(name) ||
        expanded > maximumRczMemberBytes ||
        compressed > maximumRczArchiveBytes ||
        (expandedTotal += expanded) > maximumRczExpandedBytes) {
      _fail('Duplicate member or archive resource limit exceeded.');
    }
    final localAt = directory.u32(at + 42);
    if (localAt + 30 > directoryAt) _fail('Invalid ZIP member offset.');
    final local = _View(_readAt(file, localAt, 30));
    final localNameSize = local.u16(26), localExtra = local.u16(28);
    final dataOffset = localAt + 30 + localNameSize + localExtra;
    if (local.u32(0) != 0x04034b50 ||
        local.u16(4) != version ||
        local.u16(6) != flags ||
        local.u16(8) != method ||
        localNameSize != nameSize ||
        dataOffset + compressed > directoryAt ||
        !_sameBytes(_readAt(file, localAt + 30, localNameSize), rawName)) {
      _fail('ZIP local header does not match the directory.');
    }
    if ((flags & 8) == 0 &&
        (local.u32(14) != crc || local.u32(18) != compressed || local.u32(22) != expanded)) {
      _fail('ZIP size or checksum headers disagree.');
    }
    if (method == 0 && compressed != expanded) {
      _fail('Invalid stored member size.');
    }
    if (name.endsWith('/') && expanded != 0) _fail('Invalid directory member.');
    spans.add((localAt, dataOffset + compressed));
    members[name] = RczMember._(name, method, compressed, expanded, crc, dataOffset);
    at += 46 + nameSize + extra + comment;
  }
  if (at != directory.length) _fail('Unexpected ZIP directory data.');
  spans.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  for (var i = 1; i < spans.length; ++i) {
    if (spans[i].$1 < spans[i - 1].$2) _fail('Overlapping ZIP members.');
  }
  return members;
}

String _safeName(Uint8List raw) {
  final String name;
  try {
    name = utf8.decode(raw);
  } on FormatException {
    _fail('Unsafe archive member path.');
  }
  final parts = name.split('/');
  if (name.contains('\u0000') ||
      name.contains(r'\') ||
      name.contains(':') ||
      name.startsWith('/') ||
      parts.contains('..') ||
      parts.contains('.') ||
      name.contains('//')) {
    _fail('Unsafe archive member path.');
  }
  return name;
}

Uint8List _readAt(RandomAccessFile file, int at, int count) {
  try {
    if (at < 0 || count < 0 || at + count > file.lengthSync()) {
      _fail('Archive offset is outside the file.');
    }
    file.setPositionSync(at);
    final bytes = file.readSync(count);
    if (bytes.length != count) _fail('Truncated archive.');
    return bytes;
  } on FileSystemException {
    _fail('Truncated archive.');
  }
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; ++i) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final class _View {
  _View(this.bytes) : _data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData _data;
  int get length => bytes.length;
  int u16(int at) => _data.getUint16(at, Endian.little);
  int u32(int at) => _data.getUint32(at, Endian.little);
}

/// CRC-32 (IEEE 802.3), as ZIP stores it.
final class _Crc32 {
  _Crc32([this._state = 0xffffffff]);
  final int _state;

  static final Uint32List _table = () {
    final table = Uint32List(256);
    for (var n = 0; n < 256; ++n) {
      var c = n;
      for (var k = 0; k < 8; ++k) {
        c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }();

  _Crc32 update(List<int> bytes) {
    var c = _state;
    final table = _table;
    if (bytes is Uint8List) {
      // Indexed reads of the typed list the inflater and file reads give.
      for (var i = 0; i < bytes.length; ++i) {
        c = table[(c ^ bytes[i]) & 0xff] ^ (c >> 8);
      }
    } else {
      for (final byte in bytes) {
        c = table[(c ^ byte) & 0xff] ^ (c >> 8);
      }
    }
    return _Crc32(c);
  }

  int get value => _state ^ 0xffffffff;
}
