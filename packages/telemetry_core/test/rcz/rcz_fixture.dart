// Entirely synthetic RCZ fixtures, ported from VBOOverlay
// native/tests/RczFixture.h: no private recording data in the repository.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int fixtureOrigin = 1780000000000;

Uint8List ticks(List<int> offsets) {
  final data = ByteData(offsets.length * 8);
  for (var i = 0; i < offsets.length; ++i) {
    data.setInt64(i * 8, fixtureOrigin + offsets[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

Uint8List ints(List<int> values) {
  final data = ByteData(values.length * 4);
  for (var i = 0; i < values.length; ++i) {
    data.setInt32(i * 4, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

Uint8List doubles(List<double> values) {
  final data = ByteData(values.length * 8);
  for (var i = 0; i < values.length; ++i) {
    data.setFloat64(i * 8, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));

/// The members of a small, valid single-session archive.
Map<String, Uint8List> fixtureMembers() => {
  'session.json': text(
    '{"version":1,"firstTimestamp":1780000000000,"trackName":"Synthetic","laps":[]}',
  ),
  'sessionfragment.json': text(
    '{"version":1,"firstTimestamp":1780000000000,"primaryGpsDeviceIndex":300}',
  ),
  'trackId.json': text(
    '{"track":{"traps":[{"type":3,"uniDirectional":true,"centerLatitude":300000000,"centerLongitude":120000000,"width":20000,"bearing":90000}]}}',
  ),
  'channel_1_300_0_1_1': ticks([100, 200, 300, 400, 2000]),
  'channel_1_300_0_3_1': ints([
    300000000, 120000000, 300000060, 120000060, 300000120, //
    120000120, 300000180, 120000180, 300000240, 120000240,
  ]),
  'channel_1_300_0_4_0': ints([10000, 20000, 30000, 40000, 50000]),
  'channel_5_200_10024_1_1': ticks([250, 1250]),
  'channel2_5_200_10024_10024_3': doubles([3000, 5000]),
  'channel_5_200_1002_1_1': ticks([250, 1250]),
  'channel2_5_200_1002_1002_3': doubles([0, 80]),
  'channel_6_400_0_1_1': ticks([150, 1150]),
  'channel_6_400_0_41_0': ints([120000, 140000]),
  'channel_2_301_0_1_1': ticks([150, 1150]),
  'channel_2_301_0_9_0': ints([10000, -5000]),
};

int crc32(List<int> bytes) {
  var c = 0xffffffff;
  for (final byte in bytes) {
    c ^= byte;
    for (var k = 0; k < 8; ++k) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
  }
  return c ^ 0xffffffff;
}

/// A ZIP32 archive of [files] in name order, deflated or stored.
Uint8List zip(Map<String, Uint8List> files, {bool compressed = true}) {
  final result = BytesBuilder(), directory = BytesBuilder();
  void u16(BytesBuilder b, int v) =>
      b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  void u32(BytesBuilder b, int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  final names = files.keys.toList()..sort();
  for (final key in names) {
    final name = utf8.encode(key);
    final raw = files[key]!;
    final crc = crc32(raw);
    final payload = compressed ? ZLibEncoder(raw: true, level: 6).convert(raw) : raw;
    final offset = result.length;
    u32(result, 0x04034b50);
    u16(result, 20);
    u16(result, 0);
    u16(result, compressed ? 8 : 0);
    u32(result, 0);
    u32(result, crc);
    u32(result, payload.length);
    u32(result, raw.length);
    u16(result, name.length);
    u16(result, 0);
    result
      ..add(name)
      ..add(payload);
    u32(directory, 0x02014b50);
    u16(directory, 20);
    u16(directory, 20);
    u16(directory, 0);
    u16(directory, compressed ? 8 : 0);
    u32(directory, 0);
    u32(directory, crc);
    u32(directory, payload.length);
    u32(directory, raw.length);
    u16(directory, name.length);
    u16(directory, 0);
    u16(directory, 0);
    u16(directory, 0);
    u16(directory, 0);
    u32(directory, 0);
    u32(directory, offset);
    directory.add(name);
  }
  final offset = result.length;
  final directoryBytes = directory.takeBytes();
  result.add(directoryBytes);
  u32(result, 0x06054b50);
  u32(result, 0);
  u16(result, files.length);
  u16(result, files.length);
  u32(result, directoryBytes.length);
  u32(result, offset);
  u16(result, 0);
  return result.takeBytes();
}
