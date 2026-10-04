# WEB 4 — Flutter Web `--wasm`: исправить interop-слой Web backend
**Status:** BLOCKED · **Tier:** T2, Reviewer T1 · **Owner:** — · **Depends On:** выпуск 0.5.1 · **Probe:** web

**Base SHA:** —

#### Goal

`flutter build web --wasm` собирается, модуль загружается, но первая же операция падает (`doc/web-parity.md:55`,
`:90`): `ABI v1 symbol yuv_convert_v1 returned JSValue instead of a YuvStatus number`. README объясняет это тем, что
загрузчик «relies on browser JavaScript APIs», — это неверно: Web-слой уже на `dart:js_interop` и `package:web`,
которые dart2wasm поддерживает. Цель — рабочие операции Web backend в сборке `--wasm` в Chrome либо точный список
оставшихся причин.

#### Диагноз (04.10.2026)

- `lib/src/yuv/impl/web/yuv_abi_v1_dispatch_web.dart:75-79`: результат `ccall` берётся как `callMethod<Object?>` и
  проверяется `result is num`.
- `lib/src/web/impl/js_util_compat_web.dart:58-77` (`_fromJs`): для `T` = `Object`/`Object?` значение возвращается
  без `dartify()`. В dart2js JS-число — это Dart `num`; в dart2wasm это `JSValue`, `is num` ложно → `StateError`.
- Вероятные следующие точки: `_fromJs` выбирает ветку по `T.toString()`; `_asJsObject` проверяет `is JSObject`
  (подавлен lint `invalid_runtime_check_with_js_interop_types`); `getProperty<ByteBuffer>(heap, 'buffer')` в
  `lib/src/yuv/impl/web/abi/yuv_abi_v1_wasm_memory.dart:79-81` — поведение и скорость доступа к памяти WASM под dart2wasm.

#### Architect Decision

Нужно уточнение Architect перед `TODO`. Предлагаемый порядок:

1. Точечно: `ccall` и прочие числовые результаты читать как `num` (как `_malloc` в `yuv_abi_v1_wasm_memory.dart:42`)
   или через `dartify()`; прогнать probe с `--wasm` и записать каждую следующую ошибку.
2. По итогам выбрать: точечные исправления в `js_util_compat_web.dart` или замена прослойки на типизированные
   extension types (`@JS()`) с одинаковым поведением в dart2js и dart2wasm. Публичный API не меняется.
3. Добавить прогон `--wasm` в `tool/ci/web.ps1` отдельным шагом (решение Architect: обязательный или
   информационный).
4. Обновить README, CHANGELOG и `doc/web-parity.md` по фактическому результату.

#### Scope

`lib/src/web/impl/js_util_compat_web.dart`, `lib/src/yuv/impl/web/**`, `lib/src/loader/impl/wasm_loader_web.dart`,
`tool/ci/web.ps1`, `README.md`, `CHANGELOG.md`, `doc/web-parity.md`.

#### Constraints

- `src/` и WASM-артефакты не меняются (D-17); причина на стороне Dart interop.
- Поведение JavaScript-сборки не меняется: `tool/ci/web.ps1` остаётся зелёным.
- Safari и Firefox — вне задачи (D-27).

#### Definition of Done

- `pwsh -File tool/ci/drive.ps1 integration_test/probe_web_test.dart web-server --browser-name=chrome --headless --wasm`
  — `All tests passed`, либо карточка фиксирует оставшиеся причины с доказательствами и решение Engineer.
- JavaScript-прогон `tool/ci/web.ps1` — PASS; документация описывает фактический статус `--wasm`.

#### Validation

- `pwsh -File tool/ci/web.ps1` (JavaScript-сборка, Chrome) и probe `--wasm` командой из DoD.
- Если диапазон затронул общий код (`lib/src/yuv/shared/**` и др.), набор проб расширяется по таблице `AGENTS.md`.

#### Executor Report

#### Review
