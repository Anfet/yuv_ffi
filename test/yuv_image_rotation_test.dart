@Tags(['contract'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Characterization tests for [YuvImageRotation].
///
/// These pin the behaviour that exists today.
void main() {
  group('degrees', () {
    test('each value carries its own angle', () {
      expect(YuvImageRotation.rotation0.degrees, 0);
      expect(YuvImageRotation.rotation90.degrees, 90);
      expect(YuvImageRotation.rotation180.degrees, 180);
      expect(YuvImageRotation.rotation270.degrees, 270);
    });

    test('only quarter turns exist', () {
      // This is why the IO rotate() no longer asserts on degrees % 90: the enum
      // makes any other angle unrepresentable.
      for (final rotation in YuvImageRotation.values) {
        expect(rotation.degrees % 90, 0);
      }
    });
  });

  group('swapSize', () {
    test('is true exactly for the quarter turns that transpose the frame', () {
      expect(YuvImageRotation.rotation0.swapSize, isFalse);
      expect(YuvImageRotation.rotation90.swapSize, isTrue);
      expect(YuvImageRotation.rotation180.swapSize, isFalse);
      expect(YuvImageRotation.rotation270.swapSize, isTrue);
    });
  });

  group('clockwise and counterClockwise', () {
    test('clockwise advances by one quarter turn and wraps', () {
      expect(YuvImageRotation.rotation0.clockwise, YuvImageRotation.rotation90);
      expect(YuvImageRotation.rotation90.clockwise, YuvImageRotation.rotation180);
      expect(YuvImageRotation.rotation180.clockwise, YuvImageRotation.rotation270);
      expect(YuvImageRotation.rotation270.clockwise, YuvImageRotation.rotation0);
    });

    test('counterClockwise is its exact inverse', () {
      for (final rotation in YuvImageRotation.values) {
        expect(rotation.clockwise.counterClockwise, rotation);
        expect(rotation.counterClockwise.clockwise, rotation);
      }
    });

    test('four clockwise steps return to the start', () {
      for (final rotation in YuvImageRotation.values) {
        expect(rotation.clockwise.clockwise.clockwise.clockwise, rotation);
      }
    });
  });
}
