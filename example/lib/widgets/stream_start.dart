/// Opens and attaches the camera stream for one start of a preview, handing
/// results on only while that start is still the current one.
///
/// [isCurrent] must be bound to this start, e.g. by comparing a generation
/// captured when the start began with the live one, and must turn `false`
/// once the preview is disposed. A shared "running" flag is not enough: a
/// restart or a second start may begin while [open] is still pending.
///
/// [isCurrent] is checked after every `await`:
/// - a stream [open] returns for a start that is no longer current goes to
///   [release] and is never attached, so a preview closed or restarted during
///   the permission prompt does not leave the camera running;
/// - [attach] takes ownership of the stream, so a start that stops being
///   current while [attach] waits leaves the stream to whoever stopped it and
///   only skips [onStarted];
/// - an error of a start that is no longer current does not reach [onError],
///   so it cannot hide the preview of the stream that replaced it.
///
/// [onError] receives an error of [open] or [attach] of the current start and
/// is expected to stop what [attach] set up.
Future<void> runStreamStart<S extends Object>({
  required Future<S> Function() open,
  required bool Function() isCurrent,
  required void Function(S stream) release,
  required Future<void> Function(S stream) attach,
  required void Function() onStarted,
  required void Function(Object error) onError,
}) async {
  try {
    final stream = await open();
    if (!isCurrent()) {
      release(stream);
      return;
    }
    await attach(stream);
    if (isCurrent()) {
      onStarted();
    }
  } catch (error) {
    if (isCurrent()) {
      onError(error);
    }
  }
}
