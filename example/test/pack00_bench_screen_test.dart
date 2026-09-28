import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi_example/ext.dart';
import 'package:yuv_ffi_example/pack00_bench_screen.dart';

import 'support/fake_camera.dart';

/// `Pack00BenchScreen` toggles the global `kYuvCameraPreviewPackPlanes`
/// switch to run its padded/packed A/B comparison, then must restore
/// whatever value the flag had before the screen ran, so the normal mobile
/// preview resumes with its original import mode.
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

  testWidgets('a first screen closed mid-run must not stomp a second screen\'s flag when its stale finally resolves later', (tester) async {
    // Second review's exact race: the first screen's _runBoth is not
    // cancelled by dispose(), only detached from the tree. Its still-
    // pending Future.delayed eventually fires regardless, throws out of
    // the now-unmounted setState it resumes into, and that gets caught by
    // _runBoth's own catch/finally -- which, without the mounted guard,
    // would overwrite the flag a second, unrelated screen is mid-comparison
    // with. Pre-screen value `true` for the first screen makes a stomp
    // unambiguous: the second screen's own schedule has the flag at
    // `false` (mid padded run) at the exact tick the first screen's stale
    // timer fires.
    kYuvCameraPreviewPackPlanes = true;

    await pumpBenchScreen(tester);
    expect(kYuvCameraPreviewPackPlanes, isFalse, reason: 'first screen\'s first run (padded) sets it to false');

    // Close the first screen a fraction of a second into its first run's
    // warmup, long before its pending delay resolves: dispose() restores
    // the flag to `true` (what it was before the first screen opened).
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    expect(kYuvCameraPreviewPackPlanes, isTrue);

    // Open a second screen right after. Its pre-screen value is also
    // `true` (what the first screen's dispose() just restored), so its
    // first (padded) run sets the flag to `false` again.
    await pumpBenchScreen(tester);
    expect(kYuvCameraPreviewPackPlanes, isFalse, reason: 'second screen\'s first run (padded) sets it to false too');

    // Advance to just past 13s from the *first* screen's original start
    // (0.1s before this second screen even existed): that is when its
    // stale run-0 Future.delayed resolves. At that same moment the second
    // screen, started ~0.1s later, is still inside its own first (padded)
    // run -- flag must still read false. The buggy version's stale
    // finally would force it back to the first screen's `true` here.
    await tester.pump(const Duration(milliseconds: 12950));
    expect(
      kYuvCameraPreviewPackPlanes,
      isFalse,
      reason: 'the first screen\'s stale finally must not resurrect its own pre-screen value over the second screen\'s in-flight run',
    );

    await runBothRunsToCompletion(tester);
    expect(kYuvCameraPreviewPackPlanes, isTrue, reason: 'second screen restores its own pre-screen value (true) on natural completion');
  });
}
