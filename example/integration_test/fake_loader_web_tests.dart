import 'package:flutter_test/flutter_test.dart';

import 'wasm_swap_nv_atomicity_web_test.dart' as wasm_swap;
import 'yuv_web_capabilities_web_test.dart' as capabilities;

void main() {
  group('wasm_swap_nv_atomicity_web_test.dart', wasm_swap.main);
  group('yuv_web_capabilities_web_test.dart', capabilities.main);
}
