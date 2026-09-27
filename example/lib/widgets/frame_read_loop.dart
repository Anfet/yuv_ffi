/// One result of a frame reader: either the stream has ended ([done]) or a
/// [frame] arrived. Mirrors `ReadableStreamDefaultReader.read()`.
typedef FrameReadResult<F> = ({bool done, F? frame});

/// Pulls frames from a single reader of a camera stream until the stream ends,
/// a read fails, or the stream this loop was started for is stopped or
/// replaced.
///
/// [isCurrent] must be bound to the stream this loop serves, e.g. by comparing
/// a generation captured when the reader was created with the live one. A
/// shared "running" flag is not enough: it turns `true` again once the next
/// stream starts, while a read of the old reader may still be pending.
///
/// [isCurrent] is checked before each read and after every `await`. A result
/// that arrives after the stream was stopped or replaced is not handed on: its
/// frame goes to [close] instead of [onFrame], and its error does not reach
/// [onError]. The loop then ends.
///
/// [onFrame] takes ownership of the frame it receives and must close it.
/// An error thrown by [read] or [onFrame] of the current stream is passed to
/// [onError] and ends the loop.
Future<void> runFrameReadLoop<F extends Object>({
  required Future<FrameReadResult<F>> Function() read,
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
        if (frame != null) {
          close(frame);
        }
        return;
      }
      if (result.done) {
        return;
      }
      if (frame != null) {
        await onFrame(frame);
      }
    } catch (error) {
      if (isCurrent()) {
        onError(error);
      }
      return;
    }
  }
}
