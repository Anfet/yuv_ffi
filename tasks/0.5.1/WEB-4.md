# WEB 4 — Flutter Web `--wasm`: исправить interop-слой Web backend
**Status:** IN_PROGRESS · **Tier:** T2, Reviewer T1 · **Owner:** Executor · **Depends On:** FIX 1 · **Probe:** web

**Base SHA:** — (база пула `WASM` — в FIX 1)

#### Goal

`flutter build web --wasm` собирается, модуль загружается, но первая же операция падает (`doc/web-parity.md`, строка
`--wasm`): `ABI v1 symbol yuv_convert_v1 returned JSValue instead of a YuvStatus number`. Web-слой уже на
`dart:js_interop`, который dart2wasm поддерживает; причина — в прослойке `js_util_compat_web.dart`. Цель — операции
Web backend в сборке `--wasm` в Chrome дают те же результаты, что JavaScript-сборка, либо карточка фиксирует точные
оставшиеся причины.

#### Диагноз (04.10.2026)

- `lib/src/yuv/impl/web/yuv_abi_v1_dispatch_web.dart:75-79`: результат `ccall` читается как `callMethod<Object?>` и
  проверяется `result is num`.
- `lib/src/web/impl/js_util_compat_web.dart:58-77` (`_fromJs`): для `T` = `Object`/`Object?` значение возвращается
  без `dartify()`. В dart2js JS-число — Dart `num`; в dart2wasm — `JSValue`, `is num` ложно → `StateError`. Ветка
  выбирается по `T.toString()` — хрупко для обоих компиляторов.
- `_asJsObject` проверяет `object is JSObject` (подавлен lint `invalid_runtime_check_with_js_interop_types`): под
  dart2wasm такие проверки ненадёжны.
- `lib/src/yuv/impl/web/abi/yuv_abi_v1_wasm_memory.dart:78-83` (`heapU8`): `getProperty<ByteBuffer>(heap, 'buffer')`
  идёт через `dartify()`. Если под dart2wasm это копия, а не вид на память модуля, запись в кучу теряется — это
  покажет проба (неверные байты, а не исключение).
- Рендер под `--wasm` — skwasm, а не CanvasKit. `YuvFrameRenderer` пакует 3 байта на тексель по `kIsWeb`
  (`lib/src/widgets/yuv_frame_renderer.dart:34`), что верно и под skwasm, если тот тоже премультиплицирует выборку.

#### Architect Decision

1. **Воспроизвести на базе** (негативный контроль): из корня
   `pwsh -File tool/ci/drive.ps1 integration_test/probe_web_test.dart web-server --browser-name=chrome --headless --wasm`
   — ожидается провал с `StateError`; лог — в отчёт.
2. **A1 — точечные исправления прослойки (первым):**
   - `_fromJs`: убрать выбор по `T.toString()`. Для `T`, допускающего `Object`, JS-примитивы (`isA<JSNumber>()`,
     `isA<JSBoolean>()`, `isA<JSString>()`) возвращаются через `dartify()`, остальное — JS-значение как есть. Для
     конкретного Dart-типа — `dartify()` и проверка `is T`; несовпадение — `StateError` с ожидаемым и фактическим
     типом, без молчаливого каста.
   - `_asJsObject`: `isA<JSObject>()` вместо `is JSObject`; подавление `invalid_runtime_check_with_js_interop_types`
     снять, если после правки оно не нужно.
   - `YuvAbiV1WebDispatch.call`: `callMethod<num>` (как `_malloc` в `yuv_abi_v1_wasm_memory.dart:42`), без
     промежуточного `Object?`.
   - `heapU8()`: брать `HEAPU8` как `JSUint8Array` и `.toDart` — вид на память модуля без копии в обоих компиляторах;
     перечитывать на каждом доступе, как сейчас (рост памяти отсоединяет буфер).
   - Прогнать probe `--wasm` (шаг 1). Каждую следующую ошибку записать в отчёт и исправить в пределах Scope.
3. **A2 — типизированная прослойка (только если A1 не сошёлся):** заменить вызовы `js_util_compat_web.dart` в Web
   backend на `@JS()` extension types для модуля Emscripten (`ccall`, `_malloc`, `_free`, `HEAPU8`) и фабрики модуля
   в `wasm_loader_web.dart`; публичный API не меняется. Причины отказа от A1 и логи — в отчёт. Если не сошёлся и A2 —
   `ARCHITECT_REQUIRED` с перечнем ошибок.
4. **Полный прогон под `--wasm`** через `tool/ci/drive.ps1` с `--wasm`: `probe_web_test.dart` (1188),
   `reference_web_conversions_test.dart --profile` (119), `shader_probe_web_test.dart`, `all_web_test.dart`.
   Шейдер под skwasm:
   - B1 (ожидается): 3 байта на тексель проходят — `hasShader == true`, `max_diff <= 1` во всех случаях;
   - B2: если B1 падает с `max_diff` около 255 при 3 байтах и проходит при 4 — выбор по `kIsWeb && !kIsWasm`
     в `yuv_frame_renderer.dart`, с прогоном шейдерной пробы в обеих сборках и негативным контролем;
   - иначе — `ENGINEER_REQUIRED` с данными (вариант: `YuvFrameRenderer` под `--wasm` идёт BGRA-путём).
5. **JavaScript-сборка не меняет поведение:** `pwsh -File tool/ci/web.ps1` — PASS.
6. **Время (справочно, без заявлений о скорости в документах):** время прогона пробы 1188 в обеих сборках из логов
   `drive.ps1` — в отчёт.
7. **Документация по факту:**
   - успех: README — `--wasm` поддержан (операции; шейдер — по итогу шага 4), Requirements/Platform status/Web
     backend согласованы; CHANGELOG `## 0.5.1` — `### Fixed`: `Web operations now work in flutter build web --wasm
     builds (Chrome).`; `doc/web-parity.md` — строка `--wasm` и таблица целей по новым прогонам;
   - нет успеха: README и CHANGELOG — как оставил FIX 1; `doc/web-parity.md` — новые ошибки; `ENGINEER_REQUIRED`.

#### Scope

`lib/src/web/impl/js_util_compat_web.dart`, `lib/src/yuv/impl/web/**`, `lib/src/loader/impl/wasm_loader_web.dart`,
`lib/src/loader/impl/loader_web.dart`, `lib/src/widgets/yuv_frame_renderer.dart` (только вариант B2), тесты Web в
`example/integration_test/` при необходимости, `README.md`, `CHANGELOG.md`, `doc/web-parity.md`.

#### Constraints

- `src/` и WASM-артефакты (`assets/wasm/**`) не меняются (D-17); причина — на стороне Dart interop.
- Поведение JavaScript-сборки не меняется; публичный API не меняется.
- Safari и Firefox — вне задачи (D-27). `--wasm` в CI — карточка CI 1.

#### Definition of Done

- Под `--wasm` в Chrome: `probe_web_test.dart`, `reference_web_conversions_test.dart`, `shader_probe_web_test.dart`
  и `all_web_test.dart` — `All tests passed` через `tool/ci/drive.ps1`; либо карточка фиксирует оставшиеся причины с
  логами и решение Engineer.
- `pwsh -File tool/ci/web.ps1` (JavaScript) — PASS; негативный контроль шага 1 записан.
- README, CHANGELOG и `doc/web-parity.md` описывают фактический статус `--wasm`.

#### Validation

- Executor: шаги 1, 4, 5 с командами, SHA и exit code; `bash tool/ci/scope_guard.sh <base>` — обязательные ключи
  выполнены.
- Reviewer: повторить probe `--wasm` и шейдерную пробу `--wasm` на принятом SHA; прочитать новый текст README против
  `doc/web-parity.md`.

#### Executor Report

- База `6986feb295e4b1ebbdc2139313044282d5b0daa5`, Chrome 154.0.8037.98.
- Негативный контроль: `pwsh -File tool/ci/drive.ps1 integration_test/probe_web_test.dart web-server --browser-name=chrome --headless --wasm` — exit 1; probe сообщил `got ERR StateError` на операциях.
- A1: interop преобразует JS-примитивы через `dartify()` без выбора по `T.toString()`, `ccall` возвращает `num`, `HEAPU8` читается как `JSUint8Array.toDart`.
- `dart analyze` трёх изменённых Web Dart-файлов — PASS.
- WASM: `probe_web_test.dart` (1188), `reference_web_conversions_test.dart --profile` (119), `shader_probe_web_test.dart` (shader loaded, все различия ≤1), `all_web_test.dart` — все прошли через `tool/ci/drive.ps1`. Первый shader запуск упал на Flutter `SocketException` при закрытии WebDriver; повтор с foreground ChromeDriver прошёл.
- Полный `pwsh -File tool/ci/web.ps1` на SHA `8ebc4088fab73bdf25741e30c071a1c8d11abcd8` — exit 0; JS 14 sources/64 cases, reference 119, camera smoke и три обязательных WASM цели прошли.
- `doc/web-parity.md`, README и CHANGELOG обновлены по фактическому результату. Safari/Firefox не проверялись.

#### Review
