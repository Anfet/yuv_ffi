import 'package:flutter_driver/driver_extension.dart';
import 'package:yuv_ffi_example/main.dart' as app;

Future<void> main() async {
  enableFlutterDriverExtension();
  await app.main();
}
