// Architect seed for RA-21 (audit 2026-09-27). Not a maintained test.
//
// Dumps a SHA-256 prefix of every public operation's output over a
// deterministic 3 formats x 6 sizes x 3 layouts x 22 operations matrix
// (1188 cases) to the file named by DUMP_OUT.
//
// 0.4.0 comparison: 0.4.0 has no `layout:` parameter and preserved caller
// layouts by default. To run this against a `git archive 0.4.0` tree, delete
// the three `, layout: YuvPlaneLayout.preserve` arguments; nothing else
// changes. Verified 2026-09-28: HEAD with `preserve` and 0.4.0 without it
// produce identical dumps.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

int _seed = 12345;
int _rnd() {
  _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
  return (_seed >> 8) & 0xff;
}

Uint8List _fill(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rnd()));

YuvImage _make(YuvPixelFormat f, int w, int h, String layout) {
  final cw = (w + 1) ~/ 2, ch = (h + 1) ~/ 2;
  final pad = layout == 'padded' ? 7 : 0;
  switch (f) {
    case YuvPixelFormat.i420:
      final ps = layout == 'gap' ? 2 : 1;
      final yps = layout == 'gap' ? 2 : 1;
      final y = YuvPlane(h, w * yps + pad, yps, _fill(h * (w * yps + pad)));
      final us = cw * ps + pad;
      return YuvImage.i420(w, h, yPixelStride: yps, uvPixelStride: ps, planes: [y, YuvPlane(ch, us, ps, _fill(ch * us)), YuvPlane(ch, us, ps, _fill(ch * us))], layout: YuvPlaneLayout.preserve);
    case YuvPixelFormat.nv12:
      final ps = layout == 'gap' ? 3 : 2;
      final y = YuvPlane(h, w + pad, 1, _fill(h * (w + pad)));
      final us = (cw - 1) * ps + 2 + pad;
      return YuvImage.nv12(w, h, uvPixelStride: ps, planes: [y, YuvPlane(ch, us, ps, _fill(ch * us))], layout: YuvPlaneLayout.preserve);
    case YuvPixelFormat.bgra8888:
      final ps = layout == 'gap' ? 5 : 4;
      final rs = (w - 1) * ps + 4 + pad;
      return YuvImage.bgra(w, h, planes: [YuvPlane(h, rs, ps, _fill(h * rs))], layout: YuvPlaneLayout.preserve);
  }
}

String _h(Uint8List b) => sha256.convert(b).toString().substring(0, 16);

void main() {
  test('dump', () async {
    await YuvFfi.initialize();
    final out = StringBuffer();
    final ops = <String, Object Function(YuvImage)>{
      'gray': (i) => i.applyGrayscale(),
      'bw': (i) => i.applyBlackWhite(),
      'neg': (i) => i.applyNegate(),
      'gauss': (i) => i.applyGaussianBlur(radius: 3, sigma: 2),
      'box': (i) => i.applyBoxBlur(radius: 2),
      'mean': (i) => i.applyMeanBlur(radius: 2),
      'boxRoi': (i) => i.applyBoxBlur(radius: 2, region: ui.Rect.fromLTWH(1, 1, i.width / 2, i.height / 2)),
      'meanRoi': (i) => i.applyMeanBlur(radius: 3, region: ui.Rect.fromLTWH(1, 0, i.width / 2 + 1, i.height / 2 + 1)),
      'crop': (i) => i.applyCrop(ui.Rect.fromLTWH(1, 1, (i.width - 1).toDouble(), (i.height - 1).toDouble())),
      'cropEven': (i) => i.applyCrop(ui.Rect.fromLTWH(0, 0, (i.width / 2).ceilToDouble(), (i.height / 2).ceilToDouble())),
      'cropped': (i) => i.cropped(ui.Rect.fromLTWH(1, 0, (i.width / 2).ceilToDouble(), i.height.toDouble())),
      'flipH': (i) => i.applyFlipHorizontal(),
      'flipV': (i) => i.applyFlipVertical(),
      'r90': (i) => i.applyRotation(YuvImageRotation.rotation90),
      'r180': (i) => i.applyRotation(YuvImageRotation.rotation180),
      'r270': (i) => i.applyRotation(YuvImageRotation.rotation270),
      'toI420': (i) => i.toI420(),
      'toNv12': (i) => i.toNv12(),
      'toBgra': (i) => i.toBgra(),
      'bgraBytes': (i) => i.toBgraBytes(),
      'rgbaIn': (i) => i.applyRgbaBytes(_fill(i.width * i.height * 4)),
      'swap': (i) => i.format == YuvPixelFormat.nv12 ? i.applyChromaSwap() : i,
    };
    for (final f in YuvPixelFormat.values) {
      for (final size in const [(1, 1), (2, 2), (3, 5), (16, 9), (33, 17), (127, 255)]) {
        for (final layout in const ['tight', 'padded', 'gap']) {
          for (final e in ops.entries) {
            _seed = 12345 + size.$1 * 31 + size.$2;
            final img = _make(f, size.$1, size.$2, layout);
            String r;
            try {
              final res = e.value(img);
              r = res is Uint8List ? _h(res) : '${(res as YuvImage).format.name} ${res.width}x${res.height} ${_h(res.toBytes())} src=${_h(img.toBytes())}';
            } catch (err) {
              r = 'ERR ${err.runtimeType}';
            }
            out.writeln('${f.name} ${size.$1}x${size.$2} $layout ${e.key}: $r');
          }
        }
      }
    }
    File(Platform.environment['DUMP_OUT']!).writeAsStringSync(out.toString());
  });
}
