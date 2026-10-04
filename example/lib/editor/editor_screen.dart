import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera_screen.dart';
import 'package:yuv_ffi_example/device_check/device_check_screen.dart';
import 'package:yuv_ffi_example/ext.dart';
import 'package:yuv_ffi_example/widgets/face_rect_paint.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.initialImage});

  final YuvImage? initialImage;

  @override
  State<EditorScreen> createState() => EditorScreenState();
}

class EditorScreenState extends State<EditorScreen> {
  late final YuvFramePresenter _presenter = YuvFramePresenter(useShader: true, onFramePresented: _onFramePresented);
  YuvImage? _original;
  YuvImage? image;
  YuvFrameGeometry? _geometry;
  Rect? faceBox;
  int? _lastOperationMillis;
  bool _isLoading = false;
  bool _needsPresentation = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialImage case final initial?) _setImage(initial.copy());
  }

  @override
  void dispose() {
    _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = (Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
      foreground: ui.Paint()
        ..blendMode = ui.BlendMode.difference
        ..color = Colors.white,
    );
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: const Text('YUV FFI'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeviceCheckScreen())),
            icon: const Icon(Icons.fact_check),
            tooltip: 'Device check',
          ),
          IconButton(onPressed: _takePhoto, icon: const Icon(Icons.camera), tooltip: 'Take photo'),
          IconButton(onPressed: _original == null ? null : _reset, icon: const Icon(Icons.undo), tooltip: 'Reset'),
          IconButton(onPressed: _loadImage, icon: const Icon(Icons.drive_folder_upload), tooltip: 'Load image'),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _EditorFrame(presenter: _presenter, geometry: _geometry, faceBox: faceBox, onGeometryChanged: _onGeometryChanged),
              ),
              EditorOperations(onAction: _runNamedOperation),
            ],
          ),
          if (_lastOperationMillis case final elapsed?) Positioned(right: 8, top: 8, child: Text('$elapsed msec', style: labelStyle)),
          if (image case final current?) Positioned(left: 8, top: 8, child: Text('$current', style: labelStyle)),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Future<void> _takePhoto() async {
    final result = await Navigator.of(context).push<YuvImage>(
      MaterialPageRoute(
        builder: (_) => const CameraScreen(),
        settings: const RouteSettings(name: 'camera'),
      ),
    );
    if (!mounted || result == null) return;
    _setImage(result);
  }

  void _reset() {
    final original = _original;
    if (original == null) return;
    setState(() {
      image = original.copy();
      faceBox = null;
      _lastOperationMillis = null;
    });
    _presentCurrent();
  }

  Future<void> _loadImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final Uint8List bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        final decoded = frame.image;
        try {
          final width = decoded.width;
          final height = decoded.height;
          final rgba = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (!mounted || rgba == null) return;
          _setImage(YuvImage.bgra(width, height)..applyRgbaBytes(rgba.buffer.asUint8List()));
        } finally {
          decoded.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> detectFace() async {
    final current = image;
    if (current == null) return;
    final detector = FaceDetector(
      options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.accurate, enableTracking: true),
    );
    try {
      final input = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ? current.toBgra().toInputImage() : current.toNv12().toInputImage();
      final faces = await detector.processImage(input);
      if (!mounted) return;
      faces.sort((a, b) => _area(b.boundingBox).compareTo(_area(a.boundingBox)));
      setState(() => faceBox = faces.firstOrNull?.boundingBox);
    } finally {
      detector.close().ignore();
    }
  }

  void _runNamedOperation(EditorOperation operation) {
    final current = image;
    if (current == null) return;
    if (operation == EditorOperation.faceDetection) {
      detectFace();
      return;
    }
    final watch = Stopwatch()..start();
    switch (operation) {
      case EditorOperation.rotateClockwise:
        current.applyRotation(YuvImageRotation.rotation90);
      case EditorOperation.rotateCounterclockwise:
        current.applyRotation(YuvImageRotation.rotation270);
      case EditorOperation.flipVertical:
        current.applyFlipVertical();
      case EditorOperation.flipHorizontal:
        current.applyFlipHorizontal();
      case EditorOperation.crop:
        current.applyCrop(Rect.fromLTRB(current.width * .15, current.height * .15, current.width * .85, current.height * .75));
      case EditorOperation.grayscale:
        current.applyGrayscale();
      case EditorOperation.blackWhite:
        current.applyBlackWhite();
      case EditorOperation.negate:
        current.applyNegate();
      case EditorOperation.gaussianBlur:
        current.applyGaussianBlur(radius: 10, sigma: 10);
      case EditorOperation.meanBlur:
        current.applyMeanBlur(radius: 10);
      case EditorOperation.boxBlur:
        current.applyBoxBlur(radius: 10);
      case EditorOperation.toI420:
        image = current.toI420();
      case EditorOperation.toNv12:
        image = current.toNv12();
      case EditorOperation.toBgra:
        image = current.toBgra();
      case EditorOperation.faceDetection:
        throw StateError('Handled before timing the operation.');
    }
    watch.stop();
    setState(() => _lastOperationMillis = watch.elapsedMilliseconds);
    _presentCurrent();
  }

  void _setImage(YuvImage value) {
    setState(() {
      image = value;
      _original = value.copy();
      faceBox = null;
      _lastOperationMillis = null;
    });
    _presentCurrent();
  }

  void _presentCurrent() {
    final current = image;
    if (current == null) return;
    if (!_presenter.present(current)) _needsPresentation = true;
  }

  void _onFramePresented() {
    if (!_needsPresentation || !mounted) return;
    _needsPresentation = false;
    _presentCurrent();
  }

  void _onGeometryChanged(YuvFrameGeometry value) {
    if (_geometry != value) setState(() => _geometry = value);
  }
}

class _EditorFrame extends StatelessWidget {
  const _EditorFrame({required this.presenter, required this.geometry, required this.faceBox, required this.onGeometryChanged});

  final YuvFramePresenter presenter;
  final YuvFrameGeometry? geometry;
  final Rect? faceBox;
  final ValueChanged<YuvFrameGeometry> onGeometryChanged;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      YuvFrameView(presenter: presenter, fit: YuvFrameFit.contain, onGeometryChanged: onGeometryChanged),
      if (faceBox case final box?)
        if (geometry case final currentGeometry?)
          CustomPaint(
            painter: FaceRectPainter(rect: box, geometry: currentGeometry, strokeWidth: 10),
          ),
    ],
  );
}

enum EditorOperation {
  rotateClockwise,
  rotateCounterclockwise,
  flipVertical,
  flipHorizontal,
  crop,
  grayscale,
  blackWhite,
  negate,
  gaussianBlur,
  meanBlur,
  boxBlur,
  faceDetection,
  toI420,
  toNv12,
  toBgra,
}

class EditorOperations extends StatelessWidget {
  const EditorOperations({super.key, required this.onAction});

  final ValueChanged<EditorOperation> onAction;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    child: Wrap(
      spacing: 12,
      children: [
        _action(EditorOperation.rotateClockwise, const Icon(Icons.rotate_right, size: 32), 'Rotate Clockwise'),
        _action(EditorOperation.rotateCounterclockwise, const Icon(Icons.rotate_left, size: 32), 'Rotate Counterclockwise'),
        _action(EditorOperation.flipVertical, const Icon(CupertinoIcons.arrow_up_arrow_down, size: 32), 'Flip vertically'),
        _action(EditorOperation.flipHorizontal, const Icon(CupertinoIcons.arrow_left_right, size: 32), 'Flip horizontally'),
        _action(EditorOperation.crop, const Icon(Icons.crop, size: 32), 'crop image'),
        _action(EditorOperation.grayscale, const Icon(CupertinoIcons.color_filter, size: 32), 'Grayscale'),
        _action(EditorOperation.blackWhite, const Icon(Icons.filter_b_and_w, size: 32), 'Black&White'),
        _action(EditorOperation.negate, const Icon(Icons.invert_colors, size: 32), 'Negate'),
        _action(EditorOperation.gaussianBlur, const Icon(Icons.blur_on, size: 32), 'Gaussian blur'),
        _action(EditorOperation.meanBlur, const Icon(Icons.blur_linear, size: 32), 'Mean blur'),
        _action(EditorOperation.boxBlur, const Icon(Icons.crop_square, size: 32), 'Box blur'),
        _action(EditorOperation.faceDetection, const Icon(Icons.face_outlined, size: 32), 'Face detection'),
        _action(EditorOperation.toI420, const Text('To I420', style: TextStyle(fontSize: 12)), 'To I420'),
        _action(EditorOperation.toNv12, const Text('To NV12', style: TextStyle(fontSize: 12)), 'To NV12'),
        _action(EditorOperation.toBgra, const Text('To BGRA', style: TextStyle(fontSize: 12)), 'To BGRA8888'),
      ],
    ),
  );

  Widget _action(EditorOperation operation, Widget icon, String tooltip) =>
      IconButton(onPressed: () => onAction(operation), icon: icon, tooltip: tooltip);
}

double _area(Rect rect) => rect.width * rect.height;
