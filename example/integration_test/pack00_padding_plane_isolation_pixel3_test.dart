import 'dart:convert';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';

/// PACK-00: `pack00_pack_vs_padded_pixel3_test.dart` compares the padded and
/// packed import inside a real, running preview subscription. This file
/// isolates *which plane's* padding drives any cost difference, and separates
/// the import (packing copy) cost from `applyRotation`/`toBgraBytes` cost, on
/// a real camera frame captured once and then re-measured offline (no camera
/// pipeline running), the same isolation `rotate_padding_isolated_pixel3_test.dart`
/// and `rotate_under_camera_load_pixel3_test.dart` used for VIEW-03.
///
/// `rotate_padding_isolated_pixel3_test.dart` padded Y and U/V together and
/// could not attribute its 7x rotate slowdown to one plane; this file builds
/// three synthetic variants of the same captured content -- Y padded only,
/// chroma (U/V) padded only, and both padded, each against an all-tight
/// baseline -- and measures the packing copy itself alongside rotate and BGRA.
///
/// Run (from `example/`), screen on:
/// ```
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/pack00_padding_plane_isolation_pixel3_test.dart \
///   -d 8B1X11QLW --profile
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PACK-00 Pixel 3: which plane padding drives the cost, import vs rotate vs BGRA', (tester) async {
    await YuvFfi.initialize();

    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'a physical camera must be available on the driving device');
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
    await controller.initialize();
    addTearDown(controller.dispose);

    // Capture one real padded frame the same way the mobile preview does
    // (padded import, kYuvCameraPreviewPackPlanes stays false here), then
    // stop the stream: everything below re-measures this same content with no
    // camera pipeline running, isolating layout from camera load.
    kYuvCameraPreviewPackPlanes = false;
    YuvImage? capturedPadded;
    final subscription = CameraPlatform.instance.onStreamedFrameAvailable(controller.cameraId).listen((data) {
      capturedPadded ??= CameraImage.fromPlatformInterface(data).toYuvImage();
    });
    final captureStopwatch = Stopwatch()..start();
    while (capturedPadded == null && captureStopwatch.elapsed < const Duration(seconds: 10)) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final source = capturedPadded;
    expect(source, isNotNull, reason: 'no camera frame was captured to build the padding-isolation variants from');
    expect(
      source!.format,
      YuvPixelFormat.i420,
      reason: 'this isolation assumes the Android I420 path, matching applyRotation() usage in the mobile preview',
    );

    final width = source.width;
    final height = source.height;
    final yPlane = source.yPlane;
    final uPlane = source.uPlane;
    final vPlane = source.vPlane;

    /// Builds a variant of [source]'s content with [padY]/[padChroma]
    /// controlling whether that plane keeps the captured padded row stride
    /// (`true`) or is repacked tight (`false`). Both variants hold the exact
    /// same visible samples -- only row stride differs -- so a speed
    /// difference is attributable to layout alone.
    YuvImage buildVariant({required bool padY, required bool padChroma}) {
      YuvPlane project(YuvPlane plane, int columns, bool keepPadding) {
        if (keepPadding) return plane.copy();
        final tight = Uint8List(plane.height * columns * plane.pixelStride);
        for (var row = 0; row < plane.height; row++) {
          for (var col = 0; col < columns; col++) {
            for (var b = 0; b < plane.pixelStride; b++) {
              tight[row * columns * plane.pixelStride + col * plane.pixelStride + b] =
                  plane.bytes[row * plane.rowStride + col * plane.pixelStride + b];
            }
          }
        }
        return YuvPlane(plane.height, columns * plane.pixelStride, plane.pixelStride, tight);
      }

      final chromaWidth = (width + 1) ~/ 2;
      return YuvImage.i420(
        width,
        height,
        planes: [project(yPlane, width, padY), project(uPlane, chromaWidth, padChroma), project(vPlane, chromaWidth, padChroma)],
      );
    }

    final allTight = buildVariant(padY: false, padChroma: false);
    final yPaddedOnly = buildVariant(padY: true, padChroma: false);
    final chromaPaddedOnly = buildVariant(padY: false, padChroma: true);
    final bothPadded = buildVariant(padY: true, padChroma: true);

    const warmup = 5;
    const runs = 20;
    final frequency = Stopwatch().frequency;

    Map<String, double> timeOp(YuvImage Function() build, void Function(YuvImage image) op) {
      for (var i = 0; i < warmup; i++) {
        op(build());
      }
      final samplesUs = <double>[];
      for (var i = 0; i < runs; i++) {
        final image = build();
        final sw = Stopwatch()..start();
        op(image);
        sw.stop();
        samplesUs.add(sw.elapsedTicks * 1000000 / frequency);
      }
      samplesUs.sort();
      return {
        'n': samplesUs.length.toDouble(),
        'median_ms': samplesUs[samplesUs.length ~/ 2] / 1000,
        'p95_ms': samplesUs[(samplesUs.length * 0.95).floor().clamp(0, samplesUs.length - 1)] / 1000,
        'min_ms': samplesUs.first / 1000,
        'max_ms': samplesUs.last / 1000,
      };
    }

    // Import cost: repacking the captured padded content into a tight plane,
    // measured directly (not inferred from earlier "~1-2 ms" assumptions).
    YuvPlane packPlane(YuvPlane plane, int columns) {
      final tight = Uint8List(plane.height * columns * plane.pixelStride);
      for (var row = 0; row < plane.height; row++) {
        for (var col = 0; col < columns; col++) {
          for (var b = 0; b < plane.pixelStride; b++) {
            tight[row * columns * plane.pixelStride + col * plane.pixelStride + b] = plane.bytes[row * plane.rowStride + col * plane.pixelStride + b];
          }
        }
      }
      return YuvPlane(plane.height, columns * plane.pixelStride, plane.pixelStride, tight);
    }

    final chromaWidth = (width + 1) ~/ 2;
    final importAllPlanesUs = <double>[];
    for (var i = 0; i < warmup; i++) {
      packPlane(yPlane, width);
      packPlane(uPlane, chromaWidth);
      packPlane(vPlane, chromaWidth);
    }
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      packPlane(yPlane, width);
      packPlane(uPlane, chromaWidth);
      packPlane(vPlane, chromaWidth);
      sw.stop();
      importAllPlanesUs.add(sw.elapsedTicks * 1000000 / frequency);
    }
    importAllPlanesUs.sort();

    final rotateAllTight = timeOp(() => allTight.copy(), (image) => image.applyRotation(YuvImageRotation.rotation270));
    final rotateYPaddedOnly = timeOp(() => yPaddedOnly.copy(), (image) => image.applyRotation(YuvImageRotation.rotation270));
    final rotateChromaPaddedOnly = timeOp(() => chromaPaddedOnly.copy(), (image) => image.applyRotation(YuvImageRotation.rotation270));
    final rotateBothPadded = timeOp(() => bothPadded.copy(), (image) => image.applyRotation(YuvImageRotation.rotation270));

    final bgraAllTight = timeOp(() => allTight.copy(), (image) => image.toBgraBytes());
    final bgraYPaddedOnly = timeOp(() => yPaddedOnly.copy(), (image) => image.toBgraBytes());
    final bgraChromaPaddedOnly = timeOp(() => chromaPaddedOnly.copy(), (image) => image.toBgraBytes());
    final bgraBothPadded = timeOp(() => bothPadded.copy(), (image) => image.toBgraBytes());

    // adb logcat truncates a single long I/flutter line (~4KB): two prints,
    // not one, so neither is silently cut off in the captured output.
    debugPrint(
      jsonEncode({
        'card': 'PACK-00',
        'phase': 'padding_plane_isolation_geometry',
        'device': 'pixel3',
        'platform': Platform.operatingSystem,
        'frame_size': '${width}x$height',
        'captured_y_bytes_per_row': yPlane.bytesPerRow,
        'captured_y_pixel_stride': yPlane.pixelStride,
        'captured_chroma_bytes_per_row': uPlane.bytesPerRow,
        'captured_chroma_pixel_stride': uPlane.pixelStride,
        'chroma_width': chromaWidth,
        'tight_y_bytes_per_row': width * yPlane.pixelStride,
        'tight_chroma_bytes_per_row': chromaWidth * uPlane.pixelStride,
        'import_all_planes_us': {
          'n': importAllPlanesUs.length.toDouble(),
          'median_ms': importAllPlanesUs[importAllPlanesUs.length ~/ 2] / 1000,
          'min_ms': importAllPlanesUs.first / 1000,
          'max_ms': importAllPlanesUs.last / 1000,
        },
      }),
    );
    debugPrint(
      jsonEncode({
        'card': 'PACK-00',
        'phase': 'padding_plane_isolation_rotate',
        'device': 'pixel3',
        'rotate_all_tight': rotateAllTight,
        'rotate_y_padded_only': rotateYPaddedOnly,
        'rotate_chroma_padded_only': rotateChromaPaddedOnly,
        'rotate_both_padded': rotateBothPadded,
      }),
    );
    debugPrint(
      jsonEncode({
        'card': 'PACK-00',
        'phase': 'padding_plane_isolation_bgra',
        'device': 'pixel3',
        'bgra_all_tight': bgraAllTight,
        'bgra_y_padded_only': bgraYPaddedOnly,
        'bgra_chroma_padded_only': bgraChromaPaddedOnly,
        'bgra_both_padded': bgraBothPadded,
      }),
    );

    expect(rotateAllTight['n'], greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
