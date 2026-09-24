import 'dart:convert';
import 'dart:typed_data';

/// Exact v1 bytes emitted by `YuvImage.save` at the published 0.2.4 tag.
///
/// An I420 2x2 frame with planes `[1, 2, 3, 4]`, `[5]`, `[6]`. The 0.2.4
/// writer appends zero padding after the logical payload. Checked with
/// `tool/migration/export_v1_migration_024_test.dart` on the 0.2.4 tag.
final Uint8List published024V1I4202x2 = Uint8List.fromList(
  base64Decode(
    'MgAAAHsidmVyc2lvbiI6MSwiZm9ybWF0IjoiaTQyMCIsIndpZHRoIjoyLCJoZWlnaHQiOjJ9AwIAAAACAAAAAQAAAAQAAAABAgMEAQAAAAEAAAABAAAAAQAAAAUBAAAAAQAAAAEAAAABAAAABgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  ),
);
