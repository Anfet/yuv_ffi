import 'dart:convert';
import 'dart:typed_data';

/// Exact v1 bytes emitted by `YuvCodec.encode` at 0.3.0 commit `42c2ae1`.
///
/// An I420 2x2 frame with planes `[1, 2, 3, 4]`, `[5]`, `[6]`. Checked at that
/// commit by `tool/migration/export_v1_migration_030_test.dart`, whose 0.3.0
/// `load()`/`save()` round-trip reproduces these bytes exactly.
final Uint8List historicalV1I4202x2 = Uint8List.fromList(
  base64Decode(
    'MgAAAHsidmVyc2lvbiI6MSwiZm9ybWF0IjoiaTQyMCIsIndpZHRoIjoyLCJoZWlnaHQiOjJ9AwIAAAACAAAAAQAAAAQAAAABAgMEAQAAAAEAAAABAAAAAQAAAAUBAAAAAQAAAAEAAAABAAAABg==',
  ),
);
