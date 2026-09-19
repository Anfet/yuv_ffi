import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Characterization tests for [YuvImageRotation] (YUV-27).
///
/// These pin the behaviour that exists today. `toZero()` in particular is
/// documented here rather than changed: the card requires evidence of an actual
/// defect before its semantics are touched, and none has been produced.
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

  group('toZero characterization', () {
    // The only caller in this repository is the example camera preview:
    //   yuv.rotate(rotation.toZero())
    // where `rotation` is the camera sensor orientation. The method currently
    // returns the receiver, so that call rotates the frame BY the sensor angle.
    //
    // Whether that is the intended meaning of "to zero" is deliberately not
    // decided here: no failing case has been produced, so the behaviour is
    // recorded rather than changed. If a real defect ever shows up, this test is
    // what will fail and pin the change.
    test('returns the receiver unchanged for every value', () {
      for (final rotation in YuvImageRotation.values) {
        expect(rotation.toZero(), rotation, reason: '${rotation.name}.toZero() currently returns the receiver');
      }
    });

    test('is idempotent', () {
      for (final rotation in YuvImageRotation.values) {
        expect(rotation.toZero().toZero(), rotation.toZero());
      }
    });
  });
}
