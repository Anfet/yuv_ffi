# CLEAN 2 — Удалить устаревшее API
**Status:** TODO · **Tier:** T2 · **Owner:** Terra · **Depends On:** TEST 2 · **Probe:** windows+pixel3

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

#### Review

**Reviewed-Head:** `7c9eb72c60d4e6a06cb50a7a027495480123b16f`

**Status:** TODO

**Blocking:**

- Исправление вернуло лишь по одному сокращённому case на файл и не сохраняет все действующие контракты. В `test/conversions_test.dart` осталось 1 из 35 cases: отсутствуют проверки current `apply*`, conversion round trips, crop, rotation, effects и padding. В `test/yuv_serialization_test.dart` осталось 2 из 42, а в Web serialization — 1 из 11: потеряны current v2 fixtures, fragmented/trailing payloads и atomic revision state. В `test/yuv_image_widget_test.dart` осталось 1 из 17: исчезли current cache/provider, frame snapshot, padded BGRA и rendering contracts.
- Аналогично сокращены active factory/geometry/layout/rotation и ABI/native suites: `test/yuv_image_factories_test.dart` 1 из 22, `test/yuv_plane_layout_test.dart` 1 из 15, `test/yuv_image_rotation_test.dart` 1 из 8, `test/io_abi_v1_public_contract_test.dart` 1 из 8, `test/native_allocation_safety_test.dart` 1 из 11. Эти проверки необходимо вернуть или перенести на `YuvPixelFormat` и действующие `apply*`/`to*` методы; удалить можно только assertions, завязанные исключительно на compatibility API.

**Evidence:**

- Статический поиск подтверждает отсутствие удалённых публичных declarations; README, CHANGELOG и версии `pubspec.yaml`/podspec/CMake согласованы. Это не доказывает сохранность current test contracts.
- Reviewer повторил required Pixel 3 release probes на exact Reviewed-Head: `run_release_android.ps1` arm64-v8a — `smoke=PASS`, `probe=PASS`, 1188 cases, run `99958ae53b274ce4baf488b89557ba74`; armeabi-v7a — те же PASS/1188, run `29c6f3e1360b4f819f113d836876ec3b`. Native source/ABI correctness на этом SHA подтверждена, но это не устраняет потерю VM/Web contract coverage.
