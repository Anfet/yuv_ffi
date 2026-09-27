import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Shows a live camera stream frame by frame, keeping at most one frame in
/// flight and owning the decoded image it displays.
///
/// A frame is in flight from [present] until it has been decoded and drawn
/// once. While [isBusy], the preview drops incoming frames instead of queueing
/// them, so under overload intermediate frames are skipped and the screen
/// always shows the latest frame that finished. The previous [image] is
/// disposed as soon as the next one replaces it; nothing goes through the
/// global `ImageCache`, which would keep every shown frame until LRU eviction.
///
/// [onFramePresented] fires once per frame actually drawn, so a frame rate
/// derived from it is the display rate, not the camera delivery rate.
///
/// [reset] and [dispose] stop presentation: a decode still running for an
/// earlier frame is discarded and never reaches the screen or the callback.
///
/// [YuvImageWidget] remains the way to show a single, standalone image.
class YuvFramePresenter extends ChangeNotifier {
  /// Called after a presented frame has been drawn.
  final VoidCallback? onFramePresented;

  ui.Image? _image;
  bool _isBusy = false;
  bool _isDisposed = false;

  // Bumped by reset and dispose; a decode that finishes under an older value
  // belongs to a stopped stream and is dropped.
  int _generation = 0;

  /// The frame currently shown, or `null` before the first frame and after
  /// [reset]. Owned by this presenter: take a `clone()` to keep it.
  ui.Image? get image => _image;

  /// Whether a frame is still being decoded or waits to be drawn.
  bool get isBusy => _isBusy;

  /// Creates a presenter that reports drawn frames to [onFramePresented].
  YuvFramePresenter({this.onFramePresented});

  @override
  void dispose() {
    _isDisposed = true;
    _generation++;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  /// Starts showing [frame] and returns `true`, or returns `false` and drops
  /// it while another frame is in flight or after [dispose].
  ///
  /// The pixels are converted synchronously before this returns, so the
  /// caller may overwrite or reuse [frame] right away. Throws what the
  /// conversion throws; the presenter stays free in that case.
  bool present(YuvImage frame) {
    if (_isDisposed || _isBusy) {
      return false;
    }

    final width = frame.width;
    final height = frame.height;
    final bytes = frame.toBgraBytes();
    _isBusy = true;
    _decode(bytes, width, height, _generation).ignore();
    return true;
  }

  /// Drops the shown frame and any frame in flight, e.g. when the stream it
  /// came from is stopped or replaced.
  ///
  /// The busy state is kept until the discarded decode finishes, so a new
  /// stream still never has two frames in flight.
  void reset() {
    if (_isDisposed) {
      return;
    }
    _generation++;
    final previous = _image;
    _image = null;
    previous?.dispose();
    notifyListeners();
  }

  Future<void> _decode(Uint8List bytes, int width, int height, int generation) async {
    final ui.Image decoded;
    try {
      decoded = await _decodeBgra(bytes, width, height);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'yuv_ffi_example', context: ErrorDescription('decoding a preview frame')),
      );
      _isBusy = false;
      return;
    }

    if (_isDisposed || generation != _generation) {
      decoded.dispose();
      _isBusy = false;
      return;
    }

    final previous = _image;
    _image = decoded;
    previous?.dispose();
    notifyListeners();

    // Busy until the frame is on screen: two decodes finishing within one
    // vsync would otherwise both count as presented while only one is drawn.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _isBusy = false;
      if (!_isDisposed && generation == _generation) {
        onFramePresented?.call();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  // Mirrors ui.decodeImageFromPixels, which never calls back on failure and
  // would leave the presenter busy for good.
  static Future<ui.Image> _decodeBgra(Uint8List bytes, int width, int height) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: ui.PixelFormat.bgra8888);
    try {
      final codec = await descriptor.instantiateCodec();
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }
}

/// Displays the current frame of a [YuvFramePresenter] at the frame's aspect
/// ratio, or nothing before the first frame.
class YuvFrameView extends StatelessWidget {
  /// Source of the frames to display.
  final YuvFramePresenter presenter;

  /// Creates a view of [presenter]'s current frame.
  const YuvFrameView({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        final image = presenter.image;
        if (image == null) {
          return const SizedBox.shrink();
        }
        // RawImage clones the handle for its render object, so the presenter
        // may dispose its own handle as soon as the next frame replaces it.
        return AspectRatio(
          aspectRatio: image.width / image.height,
          child: RawImage(image: image, width: image.width.toDouble(), height: image.height.toDouble(), fit: BoxFit.none),
        );
      },
    );
  }
}
