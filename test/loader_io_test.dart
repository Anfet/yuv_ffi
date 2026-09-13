import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';

void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  group('native bindings loader', () {
    test('reuses one bindings instance', () {
      final first = ffiBingings;
      final second = ffiBingings;
      final third = ffiBingings;

      expect(identical(second, first), isTrue);
      expect(identical(third, first), isTrue);
    });
  }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}
