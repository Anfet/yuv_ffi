import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:yuv_ffi/src/geometry/yuv_frame_geometry.dart';
import 'package:yuv_ffi/src/widgets/yuv_frame_image_decoder.dart';
import 'package:yuv_ffi/src/widgets/yuv_frame_renderer.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Shows a live stream of [YuvImage] frames one at a time, keeping at most one
/// frame in flight and owning the decoded image it displays.
///
/// A frame is in flight from [present] until it has been decoded and drawn
/// once. While [isBusy], [present] returns `false` and drops the incoming
/// frame instead of queueing it, so under overload intermediate frames are
/// skipped and the screen always shows the latest frame that finished. The
/// previous [image] is disposed as soon as the next one replaces it; nothing
/// goes through the global `ImageCache`, which would keep every shown frame
/// until LRU eviction.
///
/// [present] copies the frame into presenter-owned storage before returning,
/// so the caller keeps ownership of the passed-in [YuvImage] and may mutate or
/// reuse it right away. By default the copy is decoded to BGRA. With
/// [useShader], packed YUV planes are uploaded through [YuvFrameRenderer] once
/// its shader has loaded, with BGRA decoding used while it loads or when the
/// platform cannot provide the shader. The decoded [ui.Image] exposed by
/// [image] belongs to the presenter; take a `clone()` to keep it past the next
/// [present], [reset], or [dispose].
///
/// [onFramePresented] fires once per frame actually drawn, so a frame rate
/// derived from it is the display rate, not the frame arrival rate.
///
/// [reset] and [dispose] stop presentation: a decode still running for an
/// earlier frame is discarded and never reaches the screen or the callback.
///
/// Use [YuvImageWidget] instead to show a single, standalone image; this
/// class is for a stream of frames where only the latest one matters and
/// intermediate frames may be dropped under load.
class YuvFramePresenter extends ChangeNotifier {
  /// Called after a presented frame has been drawn.
  final VoidCallback? onFramePresented;

  /// Whether newly presented frames should use [YuvFrameRenderer] once loaded.
  final bool useShader;

  ui.Image? _image;
  YuvFrameRenderer? _renderer;
  YuvFrameTexture? _texture;
  YuvFrameOrientation _orientation = YuvFrameOrientation.upright;
  Size? _frameSize;
  bool _isBusy = false;
  bool _isDisposed = false;

  // Bumped by reset and dispose; a decode that finishes under an older value
  // belongs to a stopped stream and is dropped.
  int _generation = 0;

  /// The frame currently shown, or `null` before the first frame, after
  /// [reset], and whenever [useShader] is `true`. Owned by this presenter:
  /// take a `clone()` to keep it.
  ui.Image? get image => useShader ? null : _image;

  /// Whether a frame is still being decoded or waits to be drawn.
  bool get isBusy => _isBusy;

  /// Whether the optional renderer has loaded its shader.
  bool get hasShader => _renderer?.hasShader ?? false;

  /// Creates a presenter that reports drawn frames to [onFramePresented].
  YuvFramePresenter({this.onFramePresented, this.useShader = false}) {
    if (useShader) {
      _loadRenderer();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _generation++;
    _image?.dispose();
    _texture?.dispose();
    _renderer?.dispose();
    _image = null;
    _texture = null;
    super.dispose();
  }

  /// Starts showing [frame] and returns `true`, or returns `false` and drops
  /// it while another frame is in flight or after [dispose].
  ///
  /// The frame is copied synchronously before this returns, so the caller may
  /// overwrite or reuse [frame] right away. Synchronous errors reading frame
  /// metadata or copying/converting its pixels are thrown from this method and
  /// leave the presenter free. Errors while decoding the copied pixels are
  /// reported through [FlutterError.onError].
  bool present(YuvImage frame, {YuvFrameOrientation orientation = YuvFrameOrientation.upright}) {
    if (_isDisposed || _isBusy) {
      return false;
    }

    final renderer = _renderer;
    final generation = _generation;
    if (useShader && renderer != null) {
      final frameSize = frame.size;
      final upload = renderer.upload(frame);
      _isBusy = true;
      _upload(upload, frameSize, orientation, generation).ignore();
    } else {
      final width = frame.width;
      final height = frame.height;
      final bytes = frame.toBgraBytes();
      _isBusy = true;
      _decode(bytes, width, height, orientation, generation).ignore();
    }
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
    final previousTexture = _texture;
    _image = null;
    _texture = null;
    _frameSize = null;
    previous?.dispose();
    previousTexture?.dispose();
    notifyListeners();
  }

  Future<void> _decode(Uint8List bytes, int width, int height, YuvFrameOrientation orientation, int generation) async {
    final ui.Image decoded;
    try {
      decoded = await decodeYuvFrameImage(bytes, width, height, ui.PixelFormat.bgra8888);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'yuv_ffi', context: ErrorDescription('decoding a preview frame')),
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
    final previousTexture = _texture;
    _image = decoded;
    _texture = null;
    _frameSize = Size(width.toDouble(), height.toDouble());
    _orientation = orientation;
    previous?.dispose();
    previousTexture?.dispose();
    notifyListeners();

    _finishPresentation(generation);
  }

  Future<void> _upload(Future<YuvFrameTexture> upload, Size frameSize, YuvFrameOrientation orientation, int generation) async {
    final YuvFrameTexture texture;
    try {
      texture = await upload;
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'yuv_ffi', context: ErrorDescription('uploading a preview frame')),
      );
      _isBusy = false;
      return;
    }

    if (_isDisposed || generation != _generation) {
      texture.dispose();
      _isBusy = false;
      return;
    }

    final previous = _image;
    final previousTexture = _texture;
    _image = null;
    _texture = texture;
    _frameSize = frameSize;
    _orientation = orientation;
    previous?.dispose();
    previousTexture?.dispose();
    notifyListeners();

    _finishPresentation(generation);
  }

  void _finishPresentation(int generation) {
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

  Future<void> _loadRenderer() async {
    final renderer = await YuvFrameRenderer.load();
    if (_isDisposed) {
      renderer.dispose();
      return;
    }
    _renderer = renderer;
  }
}

/// Displays the current frame of a [YuvFramePresenter], applying its requested
/// orientation and optional [YuvFrameFit], or nothing before the first frame.
class YuvFrameView extends StatefulWidget {
  /// Source of the frames to display.
  final YuvFramePresenter presenter;

  /// Optional fit; when omitted the view keeps the frame's aspect ratio.
  final YuvFrameFit? fit;

  /// Placement used by the geometry rendering path.
  final Alignment alignment;

  /// Called after a new display geometry has been built.
  final ValueChanged<YuvFrameGeometry>? onGeometryChanged;

  /// Creates a view of [presenter]'s current frame.
  const YuvFrameView({super.key, required this.presenter, this.fit, this.alignment = Alignment.center, this.onGeometryChanged});

  @override
  State<YuvFrameView> createState() => _YuvFrameViewState();
}

class _YuvFrameViewState extends State<YuvFrameView> {
  YuvFrameGeometry? _reportedGeometry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        final presenter = widget.presenter;
        final image = presenter._image;
        final frameSize = presenter._frameSize;
        if (frameSize == null || (image == null && presenter._texture == null)) {
          return const SizedBox.shrink();
        }
        if (widget.fit == null && presenter._orientation == YuvFrameOrientation.upright && !presenter.useShader) {
          if (image == null) {
            return const SizedBox.shrink();
          }
          // RawImage clones the handle for its render object, so the presenter
          // may dispose its own handle as soon as the next frame replaces it.
          return AspectRatio(
            aspectRatio: image.width / image.height,
            child: RawImage(image: image, width: image.width.toDouble(), height: image.height.toDouble(), fit: BoxFit.none),
          );
        }
        final uprightSize = presenter._orientation.rotation.swapSize ? frameSize.flipped : frameSize;
        if (widget.fit == null) {
          return AspectRatio(
            aspectRatio: uprightSize.aspectRatio,
            child: LayoutBuilder(builder: _buildGeometry),
          );
        }
        return LayoutBuilder(builder: _buildGeometry);
      },
    );
  }

  Widget _buildGeometry(BuildContext context, BoxConstraints constraints) {
    final presenter = widget.presenter;
    final frameSize = presenter._frameSize;
    if (frameSize == null) {
      return const SizedBox.shrink();
    }
    final geometry = YuvFrameGeometry(
      sourceSize: frameSize,
      viewSize: constraints.biggest,
      orientation: presenter._orientation,
      fit: widget.fit ?? YuvFrameFit.contain,
      alignment: widget.alignment,
    );
    if (geometry != _reportedGeometry) {
      _reportedGeometry = geometry;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _reportedGeometry == geometry) {
          widget.onGeometryChanged?.call(geometry);
        }
      });
    }
    return CustomPaint(painter: _YuvFramePainter(presenter, geometry));
  }
}

class _YuvFramePainter extends CustomPainter {
  final ui.Image? image;
  final YuvFrameRenderer? renderer;
  final YuvFrameTexture? texture;
  final YuvFrameGeometry geometry;

  _YuvFramePainter(YuvFramePresenter presenter, this.geometry)
    : image = presenter._image,
      renderer = presenter._renderer,
      texture = presenter._texture;

  @override
  void paint(Canvas canvas, Size size) {
    final renderer = this.renderer;
    final texture = this.texture;
    if (renderer != null && texture != null) {
      renderer.paint(canvas, texture, geometry);
      return;
    }
    final image = this.image;
    if (image == null) {
      return;
    }
    canvas
      ..save()
      ..clipRect(geometry.destinationRect.intersect(Offset.zero & geometry.viewSize))
      ..transform(geometry.sourceToView.storage)
      ..drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.none)
      ..restore();
  }

  @override
  bool shouldRepaint(_YuvFramePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.texture != texture || oldDelegate.renderer != renderer || oldDelegate.geometry != geometry;
}
