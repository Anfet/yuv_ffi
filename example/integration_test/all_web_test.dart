import 'package:flutter_test/flutter_test.dart';

import 'getbytes_contract_web_test.dart' as getbytes;
import 'image_cache_key_web_test.dart' as image_cache_key;
import 'nv_chroma_order_web_test.dart' as nv_chroma_order;
import 'padded_bgra_constructor_web_test.dart' as padded_bgra;
import 'probe_web_test.dart' as probe;
import 'serialization_contract_web_test.dart' as serialization;
import 'wasm_abi_v1_descriptor_staging_web_test.dart' as wasm_abi;
import 'wasm_parity_edge_cases_web_test.dart' as wasm_parity;
import 'web_ownership_regression_web_test.dart' as ownership;

void main() {
  group('getbytes_contract_web_test.dart', getbytes.main);
  group('image_cache_key_web_test.dart', image_cache_key.main);
  group('nv_chroma_order_web_test.dart', nv_chroma_order.main);
  group('padded_bgra_constructor_web_test.dart', padded_bgra.main);
  group('probe_web_test.dart', probe.main);
  group('serialization_contract_web_test.dart', serialization.main);
  group('wasm_abi_v1_descriptor_staging_web_test.dart', wasm_abi.main);
  group('wasm_parity_edge_cases_web_test.dart', wasm_parity.main);
  group('web_ownership_regression_web_test.dart', ownership.main);
}
