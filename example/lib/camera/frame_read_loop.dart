typedef YuvFrameReadResult<F> = ({bool done, F? frame});

Future<void> runYuvFrameReadLoop<F extends Object>({
  required Future<YuvFrameReadResult<F>> Function() read,
  required bool Function() isCurrent,
  required Future<void> Function(F frame) onFrame,
  required void Function(F frame) close,
  required void Function(Object error) onError,
}) async {
  while (isCurrent()) {
    try {
      final result = await read();
      final frame = result.frame;
      if (!isCurrent()) {
        if (frame != null) close(frame);
        return;
      }
      if (result.done) return;
      if (frame != null) await onFrame(frame);
    } catch (error) {
      if (isCurrent()) onError(error);
      return;
    }
  }
}
