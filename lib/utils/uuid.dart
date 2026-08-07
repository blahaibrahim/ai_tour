import 'dart:math';

final _random = Random();

/// Generates a RFC 4122 version 4 UUID.
///
/// Artifact and job ids are `uuid` columns in Postgres, so client-generated
/// ids have to be real UUIDs — a readable id like `capture-<millis>` is
/// rejected by the column type before any foreign key is even checked.
String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
