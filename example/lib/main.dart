import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/editor/editor_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const YuvExampleApp());
}

class YuvExampleApp extends StatelessWidget {
  const YuvExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(debugShowCheckedModeBanner: false, home: EditorScreen());
}

typedef MyApp = YuvExampleApp;
