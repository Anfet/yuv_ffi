# CLEAN 2 — Удалить устаревшее API
**Status:** REVIEW · **Tier:** T2 · **Owner:** Terra · **Depends On:** TEST 2 · **Probe:** windows+pixel3

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

#### Integration correction attempt #5 — Executor Report

**Result:** REVIEW

- Ветка задачи содержит актуальный `dev` (`5c873a8`). CLEAN 1 сохраняет
  удалённые PACK-00/VIEW-03 hooks и явный
  `flipAndroidCameraHorizontally`; CLEAN 2 заменяет его конфликтный удалённый
  вызов `rotation.toZero()` на текущий `applyRotation(rotation)`.
- В integration probe test сохранена директива `library;`. Dashboard взят из
  `dev`, включая принятое состояние CLEAN 1 и актуальные SPM-карточки.
- Native C, headers и generated bindings не менялись. Активные CLEAN 2 suites
  serialization, Web, widget, rotation, ABI и native не удалялись.

**Validation:**

- `flutter analyze --no-fatal-infos lib test example/lib example/integration_test/helpers/probe/probe_selection_test.dart` — PASS без warnings/errors; 55 существующих info diagnostics о library annotations.
- `flutter test test/probe/probe_selection_test.dart test/yuv_image_rotation_test.dart test/yuv_image_widget_test.dart` — PASS: 26 tests.
- Targeted `rg` по package/example/test surfaces — PASS: нет `@Deprecated`
  declarations или ссылок на удалённый public API; `git diff --check` — PASS.
- `git merge-base --is-ancestor dev HEAD` — PASS: task/CLEAN-2 включает
  текущий `dev` и готова к чистой интеграции.

#### Integration correction review

**Reviewed-Head:** `9dcd7055eac5e1dd8adbfa6c5a3e8bfb757bd91d`

**Status:** ACCEPTED

**Acceptance:**

- `dev` является предком Reviewed-Head. Единственный кодовый конфликт сохраняет
  оба контракта: CLEAN 1 передаёт `flipAndroidCameraHorizontally: true` и
  удаляет PACK-00/VIEW-03 hooks, а CLEAN 2 заменяет снятый `toZero()` на
  `applyRotation(rotation)`.
- Public surface не содержит `@Deprecated`, `DeprecatedYuvImageApi`,
  `YuvFileFormat`, `YuvImage.nv21`, `YuvFfi.ensureInitialized`,
  `bytesPerPixes` или `toZero`; удалённые source/test files отсутствуют.
  Версия согласована: `0.5.0-dev.1` в pubspec и двух podspec, package metadata
  в CMake совпадают. Активные codec, Web, widget, factory, plane-layout,
  native и reference suites сохранены.
- `flutter analyze --no-fatal-infos lib test example/lib
  example/integration_test/helpers/probe/probe_selection_test.dart` — PASS
  (55 существующих info diagnostics); актуальные CLEAN 2 tests — PASS;
  CLEAN 1 example tests — 47/47 PASS. Полный
  `flutter test --tags "smoke || contract"` с DLL из свежей CMake-сборки —
  545 PASS. Свежий `tool/ci/windows.ps1` native build и probe suite — 20/20
  PASS, 1 expected skip.
- Release probes Pixel 3 (`8B1X11QLW`) на exact Reviewed-Head: arm64-v8a —
  `smoke=PASS`, `probe=PASS`, 1188 cases, run
  `a75d32ee75e14aa7b4bc9b44777ccb0e`, evidence
  `%TEMP%\\yuv_ffi-clean2-9dcd705-review-arm64`; armeabi-v7a — те же PASS/1188,
  run `88fe8d1732384617af96e5bc5150b470`, evidence
  `%TEMP%\\yuv_ffi-clean2-9dcd705-review-armv7`. Каждый APK содержит только
  ожидаемый ABI и `libyuv_ffi.so`.

#### Integration correction #6 — Executor Report

**Result:** REVIEW

- GitHub CI Web run `36900817922` on integration head `080f28c` and a fresh
  local `pwsh -File tool/ci/web.ps1` both failed before browser execution:
  `wasm_swap_nv_atomicity_web_test.dart` was discovered but absent from the
  Web source map.
- Restored the source to the aggregate target and source/case registry.
- No package, native, generated-binding, Web-backend, or production API source
  changed.

**Validation:**

- Before the correction: `$env:FLUTTER_VERSION='3.44.9'; pwsh -File
  tool/ci/web.ps1` — FAIL, deterministic source-map assertion after WASM
  rebuild and `pub get`; unmapped source named above.
- The corrected full command reached `pub publish --dry-run`, which requires a
  clean Git tree; it will be rerun after this correction is committed.

#### Integration correction #7 — Executor Report

**Result:** REVIEW

- The first corrected full Web run passed the source map, then exposed stale
  compatibility assertions in restored Web sources: automatic I420/BGRA
  chroma-swap conversion, mutation of an existing image by static `decode`,
  and padded allocation through the removed `copy(blank:)` behavior.
- Removed only those compatibility assertions. The surviving tests cover the
  current NV12 chroma swap, immutable static decode result, normal `copy`, and
  padded serialization. The fake-WASM atomicity source now has three current
  cases and is aggregated with the other sources.
- The Web matrix has 13 sources and 62 integration cases. No package, native,
  generated-binding, Web-backend, or production API source changed.

**Validation:**

- On `0466907`, the source map passed and browser execution reached the
  restored tests. It reported the stale assertions above; the outer helper
  then incorrectly surfaced `ChromeDriver did not become ready` after the test
  action failed.
- `dart format --output=none` for the four corrected Web sources — PASS.
- `flutter analyze --no-fatal-infos` for the four corrected Web sources —
  PASS, no issues.
- Full card-local Web command will be rerun on the next clean commit.

#### Integration correction #8 — Executor Report

**Result:** REVIEW

- The next full run reached the current atomicity source but then failed the
  following ownership source: atomicity's per-test `debugReset` cleared the
  shared loader after the combined target had already run ownership's
  `setUpAll(YuvFfi.initialize)`.
- The atomicity source is now a separate drive target, alongside bootstrap and
  lifecycle sources. This preserves its loader-reset isolation and keeps the
  aggregate target's ownership initialization valid.

**Validation:**

- On `4b2e87b`, source mapping and the restored current-contract tests passed
  until `web_ownership_regression_web_test.dart`; both failures were
  `YUV WASM module is not initialized` immediately after atomicity reset.
- `$env:FLUTTER_VERSION='3.44.9'; pwsh -File tool/ci/web.ps1` on `a514c62` —
  PASS: WASM rebuild had no diff; aggregate Web, capabilities, bootstrap,
  lifecycle, and isolated atomicity targets passed; reference matrix 119
  passed. Final output: `sources=13; integration cases=62`.
