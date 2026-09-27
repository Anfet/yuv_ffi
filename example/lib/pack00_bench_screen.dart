import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';
import 'package:yuv_ffi_example/widgets/impl/yuv_camera_preview_io.dart';
import 'package:yuv_ffi_example/widgets/yuv_camera_preview.dart';

/// PACK-00 in-app release bench, temporary: reruns the VIEW-03
/// delivered/dropped/accepted/presented measurement
/// (`example/integration_test/view03_frame_path_pixel3_test.dart`,
/// `pack00_pack_vs_padded_pixel3_test.dart`) inside this app's own real
/// `--release` build instead of `flutter drive --profile` (Flutter Driver
/// refuses `--release` on non-web, so no integration_test in this repo has
/// ever measured this path in release). A user-run in-app rotate bench on
/// this device found `applyRotation` at ~9-12 ms in release, an order of
/// magnitude below the ~93 ms every `--profile` run measured -- this screen
/// checks whether the full delivered-to-presented path shows the same gap,
/// and runs both the padded and packed camera import
/// ([kYuvCameraPreviewPackPlanes]) back to back for a real release comparison.
class Pack00BenchScreen extends StatefulWidget {
  const Pack00BenchScreen({super.key});

  @override
  State<Pack00BenchScreen> createState() => _Pack00BenchScreenState();
}

class _Pack00BenchScreenState extends State<Pack00BenchScreen> {
  CameraController? controller;
  Object? error;
  String? status;
  final results = <Map<String, Object?>>[];
  bool running = false;

  @override
  void initState() {
    super.initState();
    _runBoth();
  }

  /// [kYuvCameraPreviewPackPlanes] as it was before this screen started
  /// toggling it for the A/B comparison, so leaving this screen restores the
  /// normal mobile preview's real default (dense import since PACK-01C)
  /// instead of hardcoding the value that default happened to be when this
  /// bench was written.
  final bool _packPlanesBeforeBench = kYuvCameraPreviewPackPlanes;

  @override
  void dispose() {
    debugYuvCameraPreviewMobileEvent = null;
    kYuvCameraPreviewPackPlanes = _packPlanesBeforeBench;
    controller?.dispose();
    super.dispose();
  }

  Future<void> _runBoth() async {
    setState(() => running = true);
    try {
      await _runOne(packPlanes: false, runIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      await _runOne(packPlanes: true, runIndex: 1);
    } catch (ex) {
      if (mounted) setState(() => error = ex);
    } finally {
      // dispose() already restored the flag if this screen was closed while
      // a run was still pending; doing it again here regardless of mounted
      // would race a second bench instance opened in the meantime -- this
      // finally can resolve after that instance already started its own
      // runs, and would stomp on whatever value it is mid-comparison with.
      if (mounted) {
        kYuvCameraPreviewPackPlanes = _packPlanesBeforeBench;
        setState(() => running = false);
      }
    }
  }

  Future<void> _runOne({required bool packPlanes, required int runIndex}) async {
    setState(() {
      status = 'Run $runIndex (${packPlanes ? 'packed' : 'padded'}): opening camera...';
    });
    kYuvCameraPreviewPackPlanes = packPlanes;

    final cameras = await availableCameras();
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final c = controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
    await c.initialize();
    if (!mounted) return;
    setState(() {}); // mount YuvCameraPreview so the subscription starts

    debugYuvCameraPreviewMobileClock
      ..reset()
      ..start();

    var warmedUp = false;
    var delivered = 0;
    var droppedBusy = 0;
    var droppedStale = 0;
    var accepted = 0;
    var presented = 0;
    Duration? lastDeliveredAt;
    Duration? lastAcceptedAt;
    Duration? lastYuvImageReadyAt;
    Duration? lastRotationAppliedAt;
    Duration? lastPresentedAt;
    final toYuvImageUs = <double>[];
    final rotationUs = <double>[];
    final flipUs = <double>[];
    final acceptedToPresentedUs = <double>[];
    final presentedGapUs = <double>[];

    debugYuvCameraPreviewMobileEvent = (kind, at, {reason}) {
      if (!warmedUp) return;
      switch (kind) {
        case DebugYuvCameraPreviewMobileEventKind.delivered:
          delivered++;
          lastDeliveredAt = at;
        case DebugYuvCameraPreviewMobileEventKind.droppedBeforeTransform:
          if (reason == 'busy') {
            droppedBusy++;
          } else {
            droppedStale++;
          }
        case DebugYuvCameraPreviewMobileEventKind.yuvImageReady:
          lastYuvImageReadyAt = at;
          final d = lastDeliveredAt;
          if (d != null) toYuvImageUs.add((at - d).inMicroseconds.toDouble());
        case DebugYuvCameraPreviewMobileEventKind.rotationApplied:
          lastRotationAppliedAt = at;
          final y = lastYuvImageReadyAt;
          if (y != null) rotationUs.add((at - y).inMicroseconds.toDouble());
        case DebugYuvCameraPreviewMobileEventKind.acceptedForTransform:
          accepted++;
          lastAcceptedAt = at;
          final r = lastRotationAppliedAt;
          if (r != null) flipUs.add((at - r).inMicroseconds.toDouble());
      }
    };

    void onPresented() {
      final at = debugYuvCameraPreviewMobileClock.elapsed;
      if (!warmedUp) return;
      presented++;
      final a = lastAcceptedAt;
      if (a != null) acceptedToPresentedUs.add((at - a).inMicroseconds.toDouble());
      final p = lastPresentedAt;
      if (p != null) presentedGapUs.add((at - p).inMicroseconds.toDouble());
      lastPresentedAt = at;
    }

    _onPresented = onPresented;

    setState(() => status = 'Run $runIndex (${packPlanes ? 'packed' : 'padded'}): warm-up...');
    await Future<void>.delayed(const Duration(seconds: 3));
    delivered = 0;
    droppedBusy = 0;
    droppedStale = 0;
    accepted = 0;
    presented = 0;
    toYuvImageUs.clear();
    rotationUs.clear();
    flipUs.clear();
    acceptedToPresentedUs.clear();
    presentedGapUs.clear();
    warmedUp = true;

    setState(() => status = 'Run $runIndex (${packPlanes ? 'packed' : 'padded'}): measuring 10s...');
    await Future<void>.delayed(const Duration(seconds: 10));
    warmedUp = false;
    debugYuvCameraPreviewMobileEvent = null;
    debugYuvCameraPreviewMobileClock.stop();
    _onPresented = null;

    await controller?.dispose();
    controller = null;
    if (mounted) setState(() {}); // unmount the preview before the next run reopens the camera

    final fps = presented / 10.0;
    final result = {
      'card': 'PACK-00',
      'phase': 'release_build_in_app',
      'variant': packPlanes ? 'packed' : 'padded',
      'run_index': runIndex,
      'delivered': delivered,
      'dropped_busy': droppedBusy,
      'dropped_stale': droppedStale,
      'accepted': accepted,
      'presented': presented,
      'fps': fps,
      'to_yuv_image_median_ms': _median(toYuvImageUs) / 1000,
      'rotation_median_ms': _median(rotationUs) / 1000,
      'flip_median_ms': _median(flipUs) / 1000,
      'accepted_to_presented_median_ms': _median(acceptedToPresentedUs) / 1000,
      'presented_gap_median_ms': _median(presentedGapUs) / 1000,
    };
    debugPrint('PACK-00 release bench: ${jsonEncode(result)}');
    if (mounted) setState(() => results.add(result));
  }

  YuvImage Function(YuvImage image)? get _transformNoop =>
      (image) => image;
  void Function()? _onPresented;

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = values.toList()..sort();
    return sorted[sorted.length ~/ 2];
  }

  String get _summaryText => const JsonEncoder.withIndent('  ').convert(results);

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PACK-00 release bench'),
        actions: [
          if (results.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy results to clipboard',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _summaryText));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (c != null && c.value.isInitialized)
              SizedBox(
                height: 240,
                child: YuvCameraPreview(
                  cameraController: c,
                  transform: _transformNoop,
                  onFramePresented: () => _onPresented?.call(),
                  showDebugInfo: true,
                ),
              ),
            if (status != null) Padding(padding: const EdgeInsets.all(16), child: Text(status!)),
            if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text('Error: $error')),
            if (results.isNotEmpty)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_summaryText, style: const TextStyle(fontFamily: 'monospace')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
