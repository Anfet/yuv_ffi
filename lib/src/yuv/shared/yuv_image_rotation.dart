/// Rotation angles supported by [YuvImage.rotate].
enum YuvImageRotation {
  /// 0° rotation.
  rotation0(0),

  /// 90° clockwise rotation.
  rotation90(90),

  /// 180° rotation.
  rotation180(180),

  /// 270° clockwise rotation.
  rotation270(270),
  ;

  /// Angle value in degrees.
  final int degrees;

  /// Returns `true` when width/height are swapped by this rotation.
  bool get swapSize => this == rotation90 || this == rotation270;

  /// Next clockwise rotation value.
  YuvImageRotation get clockwise => switch (this) {
        YuvImageRotation.rotation0 => YuvImageRotation.rotation90,
        YuvImageRotation.rotation90 => YuvImageRotation.rotation180,
        YuvImageRotation.rotation180 => YuvImageRotation.rotation270,
        YuvImageRotation.rotation270 => YuvImageRotation.rotation0,
      };

  /// Next counter-clockwise rotation value.
  YuvImageRotation get counterClockwise => switch (this) {
        YuvImageRotation.rotation0 => YuvImageRotation.rotation270,
        YuvImageRotation.rotation90 => YuvImageRotation.rotation0,
        YuvImageRotation.rotation180 => YuvImageRotation.rotation90,
        YuvImageRotation.rotation270 => YuvImageRotation.rotation180,
      };

  /// Returns the normalized rotation relative to zero orientation.
  YuvImageRotation toZero() => switch (this) {
        YuvImageRotation.rotation0 => YuvImageRotation.rotation0,
        YuvImageRotation.rotation90 => YuvImageRotation.rotation90,
        YuvImageRotation.rotation180 => YuvImageRotation.rotation180,
        YuvImageRotation.rotation270 => YuvImageRotation.rotation270,
      };

  const YuvImageRotation(this.degrees);
}
