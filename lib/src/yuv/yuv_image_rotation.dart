enum YuvImageRotation {
  rotation0(0),
  rotation90(90),
  rotation180(180),
  rotation270(270),
  ;

  final int degrees;

  YuvImageRotation get clockwise => switch (this) {
        YuvImageRotation.rotation0 => YuvImageRotation.rotation90,
        YuvImageRotation.rotation90 => YuvImageRotation.rotation180,
        YuvImageRotation.rotation180 => YuvImageRotation.rotation270,
        YuvImageRotation.rotation270 => YuvImageRotation.rotation0,
      };

  YuvImageRotation get counterClockwise => switch (this) {
        YuvImageRotation.rotation0 => YuvImageRotation.rotation270,
        YuvImageRotation.rotation90 => YuvImageRotation.rotation0,
        YuvImageRotation.rotation180 => YuvImageRotation.rotation90,
        YuvImageRotation.rotation270 => YuvImageRotation.rotation180,
      };

  YuvImageRotation toZero() => switch (this) {
        YuvImageRotation.rotation0 => YuvImageRotation.rotation0,
        YuvImageRotation.rotation90 => YuvImageRotation.rotation90,
        YuvImageRotation.rotation180 => YuvImageRotation.rotation180,
        YuvImageRotation.rotation270 => YuvImageRotation.rotation270,
      };

  const YuvImageRotation(this.degrees);
}
