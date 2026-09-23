# yuv_ffi 0.4.0 — задачи до релиза

Основа: [дизайн 0.4.0](doc/api-abi-0.4-design.md) и решение владельца от 2026-09-23. Native ABI v1 выпущен в 0.3.0; публичный Dart API и codec v2 ещё требуют реализации. Приёмка нового релиза отменена до выполнения задач и повторной независимой проверки.

## Сводка статусов и Tier

| ✓ | ID | Статус | Tier / модель | Зависит от | Результат |
| --- | --- | --- | --- | --- | --- |
| [ ] | REL-01 | READY | 2 · Terra | — | `YuvPixelFormat`, NV12, wire ID. |
| [ ] | REL-02 | READY | 2 · Terra | — | Живые плоскости, `markDirty`, `applyPlanes`. |
| [ ] | REL-03 | BLOCKED | 2 · Terra | 01, 02 | Фабрики, `allocate`, RGBA импорт. |
| [ ] | REL-04 | BLOCKED | 2 · Terra | 01–03, 08–10 | Все мутирующие `apply*`. |
| [ ] | REL-05 | BLOCKED | 2 · Terra | 04 | Независимые `to*`, crop/rotate, байты. |
| [ ] | REL-06 | BLOCKED | 2 · Terra | 03–05 | Deprecated совместимость. |
| [ ] | REL-07 | BLOCKED | 2 · Terra | 01–03 | Codec: запись и чтение только v2. |
| [ ] | REL-08 | READY | 2 · Terra | — | `YuvFfi.initialize` и повторы IO/Web. |
| [ ] | REL-09 | BLOCKED | 2 · Terra | 01, 08 | Capabilities операций и форматов. |
| [ ] | REL-10 | BLOCKED | 2 · Terra | 08, 09 | Типизированные ошибки ABI/loader. |
| [ ] | REL-11 | BLOCKED | 2 · Terra | 02, 05, 08 | Widget/provider и revision. |
| [ ] | REL-12 | READY | 2 · Terra | — | BGRA с `pixelStride > 4`. |
| [ ] | REL-13 | READY | 3 · Luna | — | Границы X/Y в `YuvPlane`. |
| [ ] | REL-14 | READY | 3 · Luna | — | Apple/CMake release metadata. |
| [ ] | REL-15 | READY | 2 · Terra | — | Нижняя граница Flutter/Dart. |
| [ ] | REL-16 | BLOCKED | 3 · Luna | 01–15 | README, пример, Dartdoc, CHANGELOG. |
| [ ] | REL-17 | BLOCKED | 2 · Terra | 01–16 | Gates на итоговом SHA. |
| [ ] | REL-18 | BLOCKED | 1 · Sol | 17 | Независимая приёмка 0.4.0. |

**Итого:** 7 READY, 11 BLOCKED, 0 IN_PROGRESS, 0 REVIEW, 0 DONE. `READY` означает определённый объём; `BLOCKED` — невыполненную зависимость. `DONE` возможен после отчёта исполнителя и независимой проверки, а не только после зелёных тестов. Tier 1 — архитектура и релизное решение, Tier 2 — интеграция и сложная реализация, Tier 3 — узкая проверяемая правка. Модель в таблице рекомендована, но агент не запущен; делегировать только по явному запросу пользователя. Native C менять лишь после отдельного плана и согласования по `AGENTS.md`.

## Публичный API

### REL-01 — Имя и формат

Добавить экспортируемый `YuvPixelFormat` (`i420`, `nv12`, `bgra8888`) со стабильными wire ID 1/2/3. Legacy `nv21` сохранить с историческими UV-байтами и deprecated пометкой; RGBA оставить входным форматом ABI. **Приёмка:** compile-тест корневого экспорта, проверки ID и UV-порядка на IO/Web; enum index не попадает в codec.

### REL-02 — Живые плоскости

Конструкторы копируют входные буферы. `planes/yPlane/uPlane/vPlane` и legacy `y/u/v` возвращают живые плоскости; список структурно неизменяем. После прямой записи вызывается `markDirty()`; `applyPlanes` валидирует и копирует набор, атомарно заменяет его и повышает revision один раз. Замена плоскостей делает ранее полученные ссылки устаревшими. **Приёмка:** aliasing, copy-in, revision/cache, повторное получение плоскостей и неизменность при отказе.

### REL-03 — Фабрики

Реализовать `i420/nv12/bgra`, `allocate`, `fromRgbaBytes` и геометрию из раздела 4 дизайна. I420 по умолчанию имеет chroma pixelStride 1, NV12 — 2; явные stride сохраняются. **Приёмка:** чётные и нечётные размеры, tight/padded/gapped layouts, неверные аргументы, корневой экспорт на IO/Web.

### REL-04 — Мутация

Реализовать весь набор `apply*` из дизайна: эффекты, три blur, crop, flip, rotation, format, chroma swap, RGBA и planes. Успех возвращает `identical(this)` и увеличивает revision один раз; определённые no-op и отказ не меняют байты, metadata и revision. **Приёмка:** матрица операций/форматов IO и поддерживаемого Web, padding/alpha, odd crop и blur border против reference oracle, отказ ABI.

### REL-05 — Независимые результаты

Реализовать `toI420/toNv12/toBgra`, `cropped/rotated`, `toBytes/toBgraBytes`. Источник и revision неизменны; результат владеет отдельными буферами даже для no-op. **Приёмка:** byte/aliasing тесты IO/Web, padded BGRA и semantic no-op.

### REL-06 — Старый публичный API

Старые instance-методы перенести в экспортируемый deprecated extension; фабрики/static методы, которые extension не сохраняет, оставить deprecated в типе. Сохранить in-place семантику старых `toYuv*` и `swapNv`, а также UV-порядок `nv21`. **Приёмка:** consumer compile-тест API 0.3.0, поведенческие тесты forwarding, скрытый `YuvImageImpl`; breaking change для чужих `implements YuvImage` описан.

### REL-07 — Codec v2

Писать и читать только v2 с `formatId` из REL-01. V1 отвергать `FormatException`; автоматическую миграцию и v1 writer не делать. Сохранить лимиты размеров, строгую геометрию, потоковое чтение и EOF. **Приёмка:** golden v2, фрагментированный stream, неверные поля/версия/хвост и golden v1 с отказом; документировать перекодирование данных приложением на 0.3.0 до обновления.

## Инициализация и отображение

### REL-08 — Инициализация

Экспортировать `YuvFfi.initialize()` с общим Future для одновременных вызовов, повтором после отказа и deprecated `ensureInitialized()` как forwarding. Каждый isolate инициализируется отдельно. **Приёмка:** concurrency, fail/retry и повторный вызов IO/Web; Web не объявляется полным backend.

### REL-09 — Capabilities

Вернуть неизменяемые capabilities с `YuvOperation` и проверкой source/target форматов. IO/Web отражают реальные ABI v1 symbols и ограничения Web. **Приёмка:** таблица операций/форматов; отрицательная capability даёт `UnsupportedError` до backend и без изменения revision.

### REL-10 — Типизированные ошибки

Ввести `YuvNativeException` и разделить `ArgumentError`, `UnsupportedError`, status/runtime ошибки по разделам 2 и 13 дизайна. **Приёмка:** каждый ABI status и ошибка loader покрыты тестом; отказ атомарен на IO/Web.

### REL-11 — Widget/provider

Перевести rendering на `toBgraBytes()` и ключ с revision. После прямой записи и `markDirty()` виджет обновляется. **Приёмка:** widget/provider тест с живой плоскостью, revision и padded BGRA.

## Исправления и выпуск

### REL-12 — BGRA pixel gap

Упаковывать 4 байта каждого логического пикселя по `pixelStride`, исключая gap и row padding. **Приёмка:** `width=2`, `pixelStride=5`, различимые gap/padding, точный результат и неизменный источник на IO/Web.

### REL-13 — Координаты плоскости

Проверять X/Y до вычисления общего индекса в `getPixel/setPixel`; X не должен переходить в другую строку. **Приёмка:** воспроизвести `x=-1,y=1` на старом коде, затем подтвердить отказ без изменения соседней строки; debug/release семантика совпадает.

### REL-14 — Release metadata

Заменить шаблонную идентичность Apple podspec, проверить версии CMake/pod и состав архива. **Приёмка:** валидные podspec, Apple CI builds и `flutter pub publish --dry-run` без предупреждений.

### REL-15 — Минимальный SDK

Проверить Flutter 3.38.x / Dart 3.10.x для pub get, анализа, сборки и consumer API либо поднять constraints до проверенного минимума. **Приёмка:** точные версии и логи; изменение constraints отражено как breaking change.

### REL-16 — Документация и миграция

Согласовать README, Dartdoc, пример и CHANGELOG с реализованным API; показать `markDirty()`, `applyPlanes`, NV12/legacy NV21, codec v1→v2 и ограничения Web. **Приёмка:** фрагменты компилируются; package version совпадает с верхним CHANGELOG; planned пункты названы реализованными только после проверки. Убрать устаревшие утверждения о native ABI.

### REL-17 — Release gates

На итоговом SHA запустить format/analyze/tests, bindings/symbol audit, C tests/sanitizers, IO/Web reference matrix, Android/Apple CI builds, пример и publish dry-run. **Приёмка:** таблица SHA/платформа/команда/результат; runtime отделён от сборки; пропуски и риски указаны явно.

### REL-18 — Новая приёмка

Независимо сверить реализацию с дизайном 0.4.0 и результатами REL-17. Приёмку 0.3.0 не переносить на новый API. **Приёмка:** отдельный отчёт с каждым blocker и решением о готовности к тегу/публикации; до этого задача остаётся BLOCKED.
