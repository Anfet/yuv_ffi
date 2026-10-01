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

- Удалены compatibility-слой и его публичные объявления: `DeprecatedYuvImageApi`,
  `YuvFileFormat`, legacy dispatch, `YuvImage.nv21`,
  `YuvFfi.ensureInitialized()`, `copy(blank:)`, `bytesPerPixes`, `toZero` и
  связанные forwarding API. Удалены только тесты удалённой поверхности,
  включая `test/deprecated_api_test.dart`; действующие ABI, codec, serialization
  и Web-контракты остались в наборе.
- README содержит таблицу миграции для 0.4.0/0.4.2, а верхняя запись CHANGELOG
  фиксирует breaking change. `pubspec.yaml`, оба podspec и `src/CMakeLists.txt`
  согласованы на `0.5.0-dev.1` (CMake использует числовую `0.5.0` по своему
  формату version); native C и generated bindings не менялись.
- Статический поиск по `lib/yuv_ffi.dart`, `lib/src/yuv`, `example/lib` и `test`
  не нашёл `@Deprecated` либо удалённые публичные имена. Совпадения в README и
  CHANGELOG — намеренная таблица миграции; `ensureInitialized` внутри loader
  остаётся внутренним backend API.

**Validation:**

- Подтверждённые до этого Executor-проверки: Windows probe — PASS, 22 scenarios,
  `NO-BASELINE`; `tool/ci/vm.ps1` — 284/284; native CTest — 11/11;
  `tool/ci/smoke.ps1` — PASS; `flutter analyze` — clean. Выборки TEST 2
  `smoke || contract`, `probe` и `reference` прошли в составе этой проверки.
- `FLUTTER_VERSION=3.44.9; pwsh -File tool/ci/example.ps1` — PASS (`pub get`,
  `analyze`, `build web`). Первая попытка не получила `FLUTTER_VERSION`; это
  требование скрипта, исправленное только окружением запуска.
- `RUNNER_TEMP=<fresh>; pwsh -File tool/ci/android.ps1` — PASS: APK для
  `arm64-v8a`, `armeabi-v7a`, `x86_64`; `native_app_runtime_smoke_test.dart` и
  `probe_native_test.dart` — PASS на `emulator-5554`. Общий temp CMake cache
  ссылался на worktree TEST-3, поэтому использован изолированный `RUNNER_TEMP`.
- `pwsh -File tool/ci/web.ps1` — PASS после коммита рабочей копии, который
  требуется `pub publish --dry-run`: WASM rebuilt without diff; Chrome
  154.0.8037.58; sources=9; integration cases=56; reference matrix=119.
- Pixel 3 arm64 и armv7 остаются проверкой Reviewer по `windows+pixel3` и
  изменению `src/CMakeLists.txt` соответственно.

**Commit:** `ccf8d38 Removed deprecated public API for 0.5.0`

#### Review
