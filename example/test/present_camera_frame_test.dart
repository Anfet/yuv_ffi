import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/widgets/present_camera_frame.dart';

import 'support/fake_camera.dart';

/// Records the shade of every frame handed to it instead of decoding it.
class _RecordingPresenter extends YuvFramePresenter {
  final List<int> presented = [];

  @override
  bool present(YuvImage frame) {
    presented.add(shadeOfYuv(frame));
    return true;
  }
}

// The web preview cannot run in the VM; it hands every frame to the presenter
// through presentCameraFrame, the same function as mobile and desktop, whose
// contract is checked here.
void main() {
  late _RecordingPresenter presenter;
  late List<FlutterErrorDetails> reported;
  late FlutterExceptionHandler? previousOnError;

  setUp(() {
    presenter = _RecordingPresenter();
    reported = [];
    previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
  });

  tearDown(() {
    FlutterError.onError = previousOnError;
    presenter.dispose();
  });

  test('presents the frame transform returned', () {
    final taken = presentCameraFrame(presenter, yuvFrame(40), (image) => yuvFrame(255 - shadeOfYuv(image)));
    expect(taken, isTrue);
    expect(presenter.presented, [215]);
  });

  test('presents the camera frame without transform', () {
    expect(presentCameraFrame(presenter, yuvFrame(70), null), isTrue);
    expect(presenter.presented, [70]);
  });

  test('a throwing transform drops only its frame and is reported', () {
    final taken = presentCameraFrame(presenter, yuvFrame(20), (_) => throw StateError('transform failed'));
    expect(taken, isFalse);
    expect(presenter.presented, isEmpty);
    expect(reported.single.exception, isStateError);

    expect(presentCameraFrame(presenter, yuvFrame(21), (image) => image), isTrue);
    expect(presenter.presented, [21]);
  });
}
