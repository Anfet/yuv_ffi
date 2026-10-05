import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Driver entry point for `flutter drive` against `integration_test/`.
///
/// Required by the web probe in CI: `flutter drive` needs a driver file even
/// when the test itself carries all the assertions.
Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    stdout.writeln('CI3_DIAGNOSTICS ${jsonEncode(data)}');
  },
);
