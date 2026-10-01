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
  getbytes.main();
  image_cache_key.main();
  nv_chroma_order.main();
  padded_bgra.main();
  probe.main();
  serialization.main();
  wasm_abi.main();
  wasm_parity.main();
  ownership.main();
}
