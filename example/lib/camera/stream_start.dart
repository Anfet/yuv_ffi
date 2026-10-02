Future<void> runYuvStreamStart<S extends Object>({
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
    if (isCurrent()) onStarted();
  } catch (error) {
    if (isCurrent()) onError(error);
  }
}
