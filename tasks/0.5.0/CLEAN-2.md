# CLEAN 2 — Удалить устаревшее API
**Status:** ACCEPTED · **Tier:** T2 · **Owner:** Terra · **Depends On:** TEST 2 · **Probe:** windows+pixel3

#### Goal
D-11; вместе с `deprecated_api_test`; миграция в README и CHANGELOG.

#### Architect Decision
Исполнить решение Engineer D-11 для публичного Dart API пакета: удалить
совместимые с 0.2.4/0.3.0 объявления, помеченные `@Deprecated`, вместе с
проверками именно этой совместимости. Границу задают текущие объявления
`@Deprecated` в публичной поверхности `lib/yuv_ffi.dart` и контракт
`doc/api-abi-0.4-design.md` (§§3–8); не расширять её на ABI, wire format,
обычные действующие методы или чужие deprecated API зависимостей. Исторический
дизайн 0.4.0 остаётся историей; актуальная миграция 0.5.0 описывается в README
и верхней записи CHANGELOG. После удаления переходных методов поведение
действующего `apply*`/`to*`/`YuvPixelFormat` API не меняется.

#### Scope

- Удалить экспортируемые deprecated типы, конструкторы, методы, параметры,
  алиасы и forwarding extension (в том числе `DeprecatedYuvImageApi`,
  `YuvFileFormat`, `nv21`-фабрику, `ensureInitialized`, `copy(blank:)`,
  `bytesPerPixes`, `toZero`) по фактическому перечню публичных `@Deprecated`.
  Привести внутренние вызовы и example к действующему API, если они используют
  удаляемые объявления.
- Удалить `test/deprecated_api_test.dart` и другие тесты, чей единственный
  контракт — компиляция/семантика удалённого API. В смешанных тестах удалить
  только legacy-часть, сохранив проверки действующего API и ABI; в частности
  пересмотреть `test/public_surface_test.dart` и связанные тесты example.
- Обновить README: таблица перехода 0.2.4 → 0.4.2 остаётся полезной как
  соответствие старых имён новым, но текст должен явно указывать, что в 0.5.0
  старые объявления удалены. Добавить в верхнюю запись CHANGELOG breaking
  change и короткий маршрут миграции с 0.4.0/0.4.2.
- Если эта карточка первой создаёт запись 0.5.0 в CHANGELOG, одновременно
  исполнить D-14/D-15: `0.5.0-dev.1` в `pubspec.yaml`, podspec и версии
  `src/CMakeLists.txt`, объединение записи неопубликованной 0.4.2 с 0.5.0.
  Правка `src/CMakeLists.txt` ограничена метаданными версии по D-14; native C
  исходники не менять.

#### Constraints

- `Depends On: TEST 2` — единственная зависимость. CLEAN 1 и SPM 1 не являются
  предпосылками этой карточки.
- Сохранить действующие форматы, порядок UV у NV12, codec v2, ABI v1,
  семантику операций и частичный Web backend. Не удалять тесты, защищающие эти
  контракты, только потому что в их названии есть `legacy`.
- Не редактировать сгенерированные bindings; не менять headers, ABI и native C.
  При обнаружении deprecated объявления, удаление которого требует иного
  публичного контракта, зафиксировать конкретный случай для Architect до правки.
- Новая запись CHANGELOG идёт первой, а её версия совпадает с `pubspec.yaml`;
  D-14 требует тот же номер в podspec и CMake. Не создавать release tag и не
  публиковать пакет.

#### Definition of Done

- Экспорт `lib/yuv_ffi.dart` больше не даёт deprecated объявлений;
  исходники package/example компилируются на действующем API.
- `deprecated_api_test.dart` и все проверки исключительно удалённого API
  отсутствуют; тесты нынешнего API, ABI, сериализации и Web сохранены.
- README объясняет миграцию на действующие имена и исчезновение compatibility
  API в 0.5.0; верхняя запись CHANGELOG и номера версий следуют D-14/D-15.

#### Validation

- `Probe: windows+pixel3`: верхняя граница для удаления platform-specific
  forwarding API под `lib/src/yuv/impl/**`; Executor выполняет Windows-пробу,
  Reviewer — Pixel 3 arm64. При правке `src/CMakeLists.txt` правило `src/**`
  также требует armv7, независимо от того, что правится только версия.
- По карте путей `AGENTS.md` запустить все доступные локальные `tool/ci/*`
  скрипты для фактически изменённых файлов; при `pubspec.yaml` это ключ `all`.
  Явно проверить выборки `flutter test --tags "smoke || contract"`,
  `flutter test --tags probe` и `flutter test --tags reference`, чтобы удаление
  legacy тестов не опустошило действующие группы TEST 2.
- При изменении `src/CMakeLists.txt` отдельно выполнить native CTest и
  `flutter test --tags probe`, `flutter test --tags reference` по правилу
  `src/**` из `AGENTS.md`.
- Проверить статическим поиском отсутствие оставшихся ссылок на удалённые
  публичные имена в package/example/test, успешный анализ и согласованность
  версий. В Executor Report привести перечень удалённых объявлений, тестов и
  результаты команд; `FAIL` пробы блокирует сдачу, `SLOWER` объяснить/исправить.

#### Executor Report

**Result:** REVIEW

- Восстановлены действующие контрактные проверки codec v2, Web serialization,
  cache/revision widget key, rotation, factory/geometry/layout, ABI/native
  операций и conversion reference на актуальном `YuvImage` API. Удалённым
  остаётся только `test/deprecated_api_test.dart` и проверки исключительно
  снятого compatibility API.
- Web matrix теперь явно запускает три восстановленные Web source: 12 sources,
  59 integration cases. Native C, headers и generated bindings не менялись.
- Статический поиск в public/package/example/test surface не находит удалённые
  публичные имена либо `@Deprecated` declarations.

**Validation:**

- `RUNNER_TEMP=<fresh>; pwsh -File tool/ci/vm.ps1` — PASS: 302/302 contract and
  smoke tests; `flutter analyze --no-fatal-infos lib test` — PASS.
- `flutter test --tags probe` — PASS: 20 tests, full correctness scope 1188/1188;
  `flutter test --tags reference` — PASS: 10 tests.
- `RUNNER_TEMP=<fresh>; pwsh -File tool/ci/windows.ps1` — PASS: package tests,
  reference tests, Windows release build, runtime smoke and native probe.
- `pwsh -File tool/probe/run_windows.ps1` with the fresh native build on PATH —
  PASS: 22 scenarios, every verdict `PASS`, `NO-BASELINE`, no `SLOWER`.
- `pwsh -File tool/ci/web.ps1` — PASS: Chrome 154.0.8037.58; WASM rebuild has
  no diff; 12 sources, 59 integration cases, reference matrix 119.
- `FLUTTER_VERSION=3.44.9; pwsh -File tool/ci/example.ps1` — PASS (`pub get`,
  analyze, build web).
- Reviewer must repeat Pixel 3 arm64 and armv7 on the new head: the task card
  assigns those probes to Reviewer, and corrected contract tests changed the
  reviewed SHA. The prior Pixel run `8B1X11QLW` passed 1188 cases per ABI.

**Commit:** `6bb82ed Restored active CLEAN 2 contract tests`

**Correction #4:** Restored the complete removed suites and migrated their
active contracts to `YuvPixelFormat` and the current `apply*`, `to*`,
`encodeTo` and static `decode` APIs. The remaining removals are assertions
whose sole subject was compatibility dispatch, including mutable `load`,
`copy(blank:)`, legacy plane aliases, `toZero`, and auto-converting NV21
chroma swap. Codec v2 fixtures, fragmented/trailing payload rejection,
decode ownership, factory/layout/rotation, ABI atomicity, allocation safety,
widget cache/frame-snapshot/padded-BGRA rendering, and the Web sources are
preserved.

**Validation (correction #4):**

- `flutter test --tags contract` — PASS.
- `flutter test test/yuv_image_widget_test.dart` — PASS, 17 tests.
- `flutter analyze --no-fatal-infos lib test example/integration_test` — PASS
  (existing info diagnostics only).
- `flutter test --tags probe` and `flutter test --tags reference` could not
  load `yuv_ffi.dll` from this worktree before their matrices started; run the
  Windows CI script/native build before review. No native sources, headers, or
  generated bindings changed.
- `pwsh -File tool/ci/windows.ps1` — BLOCKED before tests: its native CMake
  invocation exited 1 (`tool/ci/_common.ps1:49`). The wrapper did not retain
  the underlying CMake diagnostic. A Windows native-build repair or a fresh
  worktree with the native asset prepared is required before this card can move
  to `REVIEW`.

**Correction #5:** Fresh worktree validation showed that the CMake failure was
stale build state, not a native source problem. The restored native reference
suite also needed the current `YuvFfi.initialize()` bootstrap and current
`applyFormat`/`applyChromaSwap` composition. Removed only stale compatibility
assertions and migrated active native tests to the current capability-gated API.

**Validation (correction #5):**

- Fresh `pwsh -File tool/ci/windows.ps1` — PASS: CMake configure/build,
  probe 20/20, reference 134/134, Windows release build, runtime smoke and
  native probe integration tests.
- `pwsh -File tool/ci/vm.ps1` — PASS: analyze and 571/571 smoke/contract
  tests.
- `pwsh -File tool/probe/run_windows.ps1` with the fresh DLL on PATH — PASS:
  24/24 scenarios, every verdict `PASS`, `NO-BASELINE`, no `SLOWER`.
- Earlier Web and example evidence remains applicable: this correction changes
  only VM-native test setup and assertions; no Web source, example source,
  native source, headers, bindings, assets, package metadata, or CI script
  changed.

Reviewer runs the required Pixel 3 arm64 and armv7 release probes on the
committed correction head.

#### Review

**Reviewed-Head:** `f143278fe9e6e9386d774eac88086228ba6f5c16`

**Status:** ACCEPTED

**Acceptance:**

- Контракты, ранее потерянные на `7c9eb72`, восстановлены: `conversions` 35 cases, serialization 42, widget 17, factory 24, plane layout 15, native allocation safety 11, а Web serialization 11. Проверка diff после `61ae669` подтверждает, что correction #5 удаляет только assertions снятого compatibility API и переводит active native cases на `YuvFfi.initialize()` и текущие `apply*` методы.
- Статический поиск не нашёл `@Deprecated` declarations или удалённые exported compatibility names в package/example/test; README и верхний CHANGELOG описывают migration. `pubspec.yaml` и оба podspec содержат `0.5.0-dev.1`; `src/CMakeLists.txt` задаёт numeric `0.5.0` и exact package metadata `0.5.0-dev.1`.
- Executor evidence на этом head: Windows CI PASS (probe 20/20, reference 134/134, release/runtime smoke); VM PASS (571/571 smoke/contract); Windows probe PASS (24/24, `NO-BASELINE`, без `SLOWER`). Web и example evidence сохраняют силу, поскольку correction #5 не меняет их source, assets, metadata или CI scripts.
- Reviewer повторил release probes Pixel 3 на этом head: arm64-v8a — `smoke=PASS`, `probe=PASS`, 1188 cases, run `2e093313f7de443e83c89ef168575438`, evidence `%TEMP%\yuv_ffi-clean2-f143278-arm64`; armeabi-v7a — те же PASS/1188, run `31ab84396bb94690aad5c15ce34fcd7d`, evidence `%TEMP%\yuv_ffi-clean2-f143278-armv7`. APK каждого run содержит только ожидаемый ABI и `libyuv_ffi.so`.
