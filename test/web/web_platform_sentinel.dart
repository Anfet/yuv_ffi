import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web platform sentinel executes in a browser', () {
    expect(kIsWeb, isTrue);
  });
}
