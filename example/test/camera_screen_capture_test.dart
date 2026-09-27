import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera_screen.dart';

const List<int> _frameA = [10, 20, 30, 255];
const List<int> _frameB = [200, 150, 100, 255];

Uint8List _solidBgra(int width, int height, List<int> bgra) => Uint8List.fromList([for (int i = 0; i < width * height; i++) ...bgra]);

/// Writes [bgra] into [frame] the way the web TrackProcessor preview writes
/// every next frame into its one reused instance.
void _writeFrame(YuvImage frame, List<int> bgra) {
  frame.yPlane.assignFrom(_solidBgra(frame.width, frame.height, bgra));
  frame.markDirty();
}

void main() {
  // No camera is needed: on the test host `availableCameras` never answers, so
  // the screen stays on its progress indicator, while capture itself only goes
  // through `takePicture` and the preview's `transform` callback, which the
  // test calls the way the preview would.
  testWidgets('a frame captured from the reused web/desktop preview frame is not changed by the frames written after it', (tester) async {
    Future<Object?>? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => popped = Navigator.of(context).push<Object?>(MaterialPageRoute(builder: (_) => const CameraScreen())),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Not pumpAndSettle: the screen keeps a progress indicator spinning while
    // the camera lookup never answers on the test host.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // _CameraScreenState is private to the example, so its capture entry
    // points are reached dynamically rather than widened for the test.
    final dynamic screen = tester.state(find.byType(CameraScreen));

    final reused = YuvImage.bgra(2, 2);
    _writeFrame(reused, _frameA);

    // The same order as a tap on "Capture": takePicture waits for the next
    // frame, the preview hands frame A to transform, then keeps writing.
    final Future<void> capture = screen.takePicture();
    final returned = screen.imageCapturer(reused) as YuvImage;
    expect(identical(returned, reused), isTrue, reason: 'the preview must keep showing its own frame');

    _writeFrame(reused, _frameB);
    await tester.pump(const Duration(milliseconds: 250));
    screen.imageCapturer(reused);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    await capture;

    final captured = await popped;
    expect(captured, isA<YuvImage>());
    final frame = captured! as YuvImage;
    expect(
      frame.yPlane.bytes,
      orderedEquals(_solidBgra(2, 2, _frameA)),
      reason: 'frame B written while takePicture waited must not reach the capture',
    );
    expect(identical(frame, reused), isFalse, reason: 'the capture must own its frame, not share the reused preview instance');

    // The preview is not stopped by the capture itself: a frame written after
    // pop must not reach the captured result either.
    _writeFrame(reused, _frameB);
    expect(frame.yPlane.bytes, orderedEquals(_solidBgra(2, 2, _frameA)));
  });
}
