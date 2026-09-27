import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi_example/ext.dart';
import 'package:yuv_ffi_example/pack00_bench_screen.dart';

import 'support/fake_camera.dart';

/// PACK-01C: `Pack00BenchScreen` toggles the global `kYuvCameraPreviewPackPlanes`
/// switch to run its padded/packed A/B comparison, then must restore
/// whatever the flag was *before* the screen ran -- not hardcode it back to
/// `false`, which was only correct while padded import was the shipped
/// default. Since PACK-01C flipped that default to `true`, leaving this
/// screen used to silently leave the normal mobile preview importing padded
/// frames afterward.
void main() {
  late FakeCameraPlatform platform;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
  });

  Future<void> pumpBenchScreen(WidgetTester tester) => tester.pumpWidget(const MaterialApp(home: Pack00BenchScreen()));

  /// Drives the fake clock through both A/B runs' warmup + measurement
  /// delays (3s + 10s each, plus the 500ms gap between them) so `_runBoth`
  /// reaches its `finally` naturally, rather than leaving a `Future.delayed`
  /// Timer pending when the widget tree is torn down.
  Future<void> runBothRunsToCompletion(WidgetTester tester) async {
    for (var i = 0; i < 28; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  testWidgets('completing both A/B runs restores the flag as it was before the screen opened', (tester) async {
    kYuvCameraPreviewPackPlanes = true;

    await pumpBenchScreen(tester);
    expect(kYuvCameraPreviewPackPlanes, isFalse, reason: 'the first of the two A/B runs sets it to false while it runs');

    await runBothRunsToCompletion(tester);

    expect(kYuvCameraPreviewPackPlanes, isTrue, reason: 'must restore the value from before this screen ran, not hardcode false');
  });

  testWidgets('completing both A/B runs restores false when that was the value before the screen opened', (tester) async {
    kYuvCameraPreviewPackPlanes = false;

    await pumpBenchScreen(tester);
    await runBothRunsToCompletion(tester);

    expect(kYuvCameraPreviewPackPlanes, isFalse);
  });

  testWidgets('disposing the screen mid-run restores the flag as it was before the screen opened', (tester) async {
    kYuvCameraPreviewPackPlanes = true;

    await pumpBenchScreen(tester);
    expect(kYuvCameraPreviewPackPlanes, isFalse, reason: 'the first of the two A/B runs sets it to false while it runs');

    // Unmount mid-run, well before either run's warmup/measurement delay
    // fires: dispose() must still restore the pre-screen value, not just the
    // finally block a natural completion goes through.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    // The still-pending Future.delayed Timer from the unmounted run fires
    // harmlessly once real async work is allowed to complete; let it, so
    // this binding's teardown does not see a Timer still pending.
    await tester.pump(const Duration(seconds: 15));

    expect(kYuvCameraPreviewPackPlanes, isTrue, reason: 'must restore the value from before this screen ran, not hardcode false');
  });
}
