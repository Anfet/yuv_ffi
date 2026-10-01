# CLEAN 2 — Удалить устаревшее API
**Status:** IN_PROGRESS · **Tier:** T2 · **Owner:** Terra · **Depends On:** TEST 2 · **Probe:** windows+pixel3

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

#### Review
