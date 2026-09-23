# yuv_ffi 0.4.0 — задачи до релиза

Основа: [дизайн 0.4.0](doc/api-abi-0.4-design.md) и решение владельца от 2026-09-23. Native ABI v1 выпущен в 0.3.0; публичный Dart API и codec v2 ещё требуют реализации. Приёмка нового релиза отменена до выполнения задач и повторной независимой проверки.

## Сводка статусов и Tier

| ✓ | ID | Статус | Tier / модель | Зависит от | Ревью | Результат |
| --- | --- | --- | --- | --- | --- | --- |
| [x] | REL-01 | REVIEW (ACCEPT, follow-up) | 2 · Terra | — | R1 | `YuvPixelFormat`, NV12, wire ID. |
| [x] | REL-02 | REVIEW (ACCEPT) | 2 · Terra | — | R1 | Живые плоскости, `markDirty`, `applyPlanes`. |
| [x] | REL-03 | REVIEW (ACCEPT, rework passed) | 2 · Terra | 01, 02 | R1 | Фабрики, `allocate`, RGBA импорт. |
| [ ] | REL-04 | BLOCKED | 2 · Terra | 01–03, 08–10 | R3 | Все мутирующие `apply*`. |
| [ ] | REL-05 | BLOCKED | 2 · Terra | 04 | R3 | Независимые `to*`, crop/rotate, байты. |
| [ ] | REL-06 | BLOCKED | 2 · Terra | 03–05 | R3 | Deprecated совместимость. |
| [ ] | REL-07 | BLOCKED | 2 · Terra | 01–03 | R3 | Codec: запись и чтение только v2. |
| [ ] | REL-08 | READY | 2 · Terra | — | R2 | `YuvFfi.initialize` и повторы IO/Web. |
| [ ] | REL-09 | BLOCKED | 2 · Terra | 01, 08 | R2 | Capabilities операций и форматов. |
| [ ] | REL-10 | BLOCKED | 2 · Terra | 08, 09 | R2 | Типизированные ошибки ABI/loader. |
| [ ] | REL-11 | BLOCKED | 2 · Terra | 02, 05, 08 | R3 | Widget/provider и revision. |
| [x] | REL-12 | REVIEW (ACCEPT, follow-up) | 2 · Terra | — | R1 | BGRA с `pixelStride > 4`. |
| [x] | REL-13 | REVIEW (ACCEPT, redo passed) | 2 · Terra | — | R1 | Границы X/Y в `YuvPlane`. |
| [ ] | REL-14 | READY | 3 · Luna | — | R4 | Apple/CMake release metadata. |
| [ ] | REL-15 | READY | 2 · Terra | — | R4 | Нижняя граница Flutter/Dart. |
| [ ] | REL-16 | BLOCKED | 3 · Luna | 01–15 | R4 | README, пример, Dartdoc, CHANGELOG. |
| [ ] | REL-17 | BLOCKED | 2 · Terra | 01–16 | R5 | Gates на итоговом SHA. |
| [ ] | REL-18 | BLOCKED | 1 · Sol | 17 | R5 | Независимая приёмка 0.4.0. |

**Итого (после волны 1 и ревью R1 2026-09-23):** 3 REVIEW (ACCEPT, ждут интеграции), 2 REJECTED (доработка), 3 READY, 11 BLOCKED, 0 IN_PROGRESS, 0 DONE. 0 ARCH REQUIRED.
`READY` означает определённый объём; `BLOCKED` — невыполненную зависимость. `DONE` возможен после отчёта исполнителя и независимой проверки, а не только после зелёных тестов.

## Ревью пакета R1 (2026-09-23)

Волна 1 (REL-12, REL-01, REL-02, REL-03, REL-13) выполнена параллельно, проверена Tier 2 (Sonnet-оркестратор), затем эскалирована на Tier 1 (Opus) из-за архитектурной неоднозначности по NV12 chroma stride.

**Architect Decision — NV12 `uvPixelStride` override:** design doc §4 (строки ~253-257) описывает только *дефолтное* значение stride ("NV12 keeps `uvPixelStride = 2`"), а не верхнюю границу. Раздел plane-layout (строки ~782-795) явно разрешает произвольный больший stride: "Positive larger pixel/row strides are supported... pixel gaps are padding." todo.md (REL-03) также требует поддержки gapped layouts. Нативный ABI v1 уже адресует сэмплы через `rowStride`/`pixelStride` (`validated_view.c:94`, `yuv_kernel_v1.c:27/35`) и не завязан на `stride==2`. **Решение:** новые NV12-пути должны принимать любой `uvPixelStride >= 2` и кидать `ArgumentError` при значении < 2, без молчаливого клэмпа. Legacy `nv21` сохраняет клэмп 0.3.0 (это чинит REL-06). Проверка в codec — зона REL-07. Изменений в native C не требуется.

**Вердикты:**
- REL-12 — ACCEPT (follow-up: устаревший комментарий "decide on rowStride alone" в `yuv_web.dart:305-308`, не влияет на поведение)
- REL-01 — ACCEPT (follow-up: тест UV-порядка сравнивает только stride/format, не реальные байты; нет Web-покрытия; `@Deprecated` на `YuvFileFormat` сознательно отложен до REL-06 — зафиксировать это в описании REL-06)
- REL-02 — ACCEPT, без замечаний
- REL-03 — **REWORK ACCEPTED (2026-09-23)**. `YuvGeometry.validateImage` получил `allowLargerNvChromaStride` (default `false`, сохраняет точное поведение `nv21`); `.nv12`-конструкторы во всех трёх backend строят `_state` напрямую с флагом `true`, честно отклоняя `uvPixelStride < 2` через `ArgumentError` без клэмпа. Тесты переписаны: explicit stride выше дефолта принимается как есть (не клэмпается), stride ниже 2 кидает `ArgumentError`, добавлен regression-тест что `nv21` не затронут, добавлен реальный gapped-NV12 тест через нативный ABI v1 (`grayscale()` на `uvPixelStride: 3` с маркерными байтами 0xEE в gap, проверка что gap не тронут) плюс Web-аналог; добавлены тесты на honored explicit I420 `yPixelStride`/`uvPixelStride`. Проверено: `flutter analyze` чист, полный набор тестов зелёный (2 pre-existing environment-only failures из-за отсутствия `.dll` на хосте, не новые). Gapped-NV12 тесты (IO и Web) корректно self-skip на этой машине (нет собранной native lib / браузера) — исполнитель прямо отметил, что перед финальным релизом их нужно прогнать на окружении с реальным native/WASM.
- REL-13 — **REDO ACCEPTED (2026-09-23)**. Переделано на верной базе (`beb01e7`, подтверждено `git log`). Overflow-safe проверка `x > (rowStride - 1) ~/ pixelStride` вместо `x * pixelStride`; независимая валидация x/y до объединения в индекс; `pixelStride == 0` отдельно отклоняется. Использован `ArgumentError` вместо предложенного в фидбеке `RangeError` — верно, согласно §5 дизайна ("Constructor, coordinate, length, arithmetic, and value violations throw `ArgumentError` rather than relying on debug asserts or incidental `RangeError`"), проверено цитатой из документа. 30/30 тестов в `test/yuv_plane_validation_test.dart` проходят (включая regression, overflow, boundary-exact, debug/release parity), `flutter analyze` чист.

**Требуемая доработка:**
- REL-03 (Tier 2): в `validateImage` заменить проверку NV UV-stride на `>= 2`; `nv12` фабрика кидает `ArgumentError` при `uvPixelStride < 2`, клэмп оставить только для legacy `nv21`/unnamed-фабрики; исправить неверный тест и добавить реальный gapped-кейс (например stride 3, с меткой в gap-байтах) через ABI v1 на IO и WASM, подтвердить неизменность gap-байтов; добавить тест на honored explicit I420 stride. Если нативный kernel не переживёт gap — остановиться и эскалировать (правило AGENTS.md про native C).
- REL-13 (Tier 3, на правильной базе `beb01e7`): проверять X через `x > (rowStride - 1) ~/ pixelStride` (не переполняется), обработать `pixelStride == 0`; сохранить существующие тесты; задокументировать репродукцию `x=-1, y=1` на непропатченном коде.
- REL-01 (Tier 2, некритично, можно вместе с REL-03/06): добавить byte-level тест UV-порядка (запись/чтение реальных байт, round-trip через BGRA-конвертацию на native) + Web-аналог.
- REL-06 (для будущего исполнителя): явно включить в scope `@Deprecated` на `YuvFileFormat` и точки входа `nv21`; internal bridge-extensions (`YuvPixelFormatLegacyBridge`/`YuvFileFormatPixelFormatBridge` в `yuv_pixel_format.dart`) — оставить unexported, они являются механизмом форвардинга для REL-06, не конфликтуют с планом депрекации.

**Пакет R1 полностью принят (2026-09-23):** REL-12, REL-01, REL-02, REL-03, REL-13 все в статусе REVIEW/ACCEPT. Остаются в TODO как REVIEW (не DONE) до физической интеграции веток (Stream A: worktree agent-a0081571bd1b8b8f8; Stream B/REL-13: worktree agent-a1340668a12e5c821) в общую ветку и коммита — по правилу "ревьюер проверяет один интегрированный diff... на пакет", DONE выставляется после мёржа, не раньше. Открытые некритичные follow-up пункты (byte-level UV round-trip тест для REL-01, `@Deprecated` на `YuvFileFormat` — оба в scope REL-06) перенесены в описание REL-06 ниже.

Для работы с делегацией использются следующие правила
"D:\.projects\Model Delegation & Usage Policy.md"
"D:\.projects\agent_orchestration_protocol.md"

Исполнитель берет задачу - переводит ее в IN PROGRESS. после исполнения в REVIEW.
Исполнитель не придумывает архитектурные решения. В случае обнаружения - переводит в ARCH REQUIRED, записывает выводы и останавливается. Перезапуск производит инженер после отработки с архитектором.
Ревьюер проверяет задачи в REVIEW и переводит в DONE (с созданием коммита) или TODO с пометками что требуется доработать. После приемки ревьюер выносит DONE задачи из todo, обновляет зависимости и статусы зависимых задач.
Ревьюер не запускает задачи на выполнение.

Tier 1 (Sol 6/ Opus) — архитектура и релизное решение, Tier 2 (Terra 5.6 / Sonnet) — интеграция и сложная реализация, Tier 3 (Luna 6 / Haiku) — узкая проверяемая правка. Модель в таблице рекомендована, но агент не запущен; делегировать только по явному запросу пользователя. Native C менять лишь после отдельного плана и согласования по `AGENTS.md`.

## Параллельные группы исполнения

Группы ниже описывают будущий запуск, а не разрешают его. Стрелка внутри группы задаёт порядок интеграции из-за общих файлов; она не заменяет зависимости в сводной таблице. Разные строки одной волны можно выполнять параллельно в отдельных рабочих деревьях. Перед передачей результата следующему исполнителю изменения объединяются в общую ветку.

| Волна | Поток | Задачи и порядок | Граница параллельности |
| --- | --- | --- | --- |
| 1 | A · формат и состояние | REL-12 → REL-01 → REL-02 → REL-03 | Один поток: `yuv_image_state.dart`, формат, интерфейс и backend-конструкторы пересекаются. |
| 1 | B · плоскость | REL-13 | Отдельный `yuv_plane.dart`; закончить интеграцию до REL-02. |
| 1 | C · загрузка | REL-08 | Отдельные initializer/loader; продолжение REL-09 ждёт принятия REL-01. |
| 1 | D · упаковка | REL-14 | Podspec/CMake; не менять native C. |
| 1 | E · SDK | REL-15 | Проверка SDK и при необходимости constraints; согласовать правку `pubspec.yaml` с REL-14. |
| 2 | C · capabilities и ошибки | REL-09 → REL-10 | После R1 и REL-08; один поток в инициализации/dispatch. |
| 2 | F · codec | REL-07 | После R1; отдельный `yuv_codec.dart`, параллельно потокам C и позднее G. |
| 3 | G · операции | REL-04 → REL-05 → REL-06 | После R1 и R2; один поток через общий интерфейс и IO/Web реализации. |
| 3 | H · отображение | REL-11 | После REL-05; параллельно REL-06 при раздельных файлах widget/provider и API. |
| 4 | I · документация | REL-16 | После реализации REL-01–15; включает результат потоков D и E. |
| 5 | J · финальная проверка | REL-17 → REL-18 | После R3 и R4; gates предшествуют независимой приёмке. |

Внутри потока задачи выполняются последовательно. Если несколько задач одного пакета зависят друг от друга, следующая может опираться на уже интегрированный результат со статусом `REVIEW`; статус `DONE` до пакетного ревью не выставляется. При отклонении ранней задачи её зависимые результаты возвращаются на доработку. Между пакетами R1/R2/R3/R4 зависимость открывается после принятия соответствующего пакета. REL-14 и REL-15 можно завершить в первой волне, а проверять вместе с документацией в R4. `ARCH REQUIRED` останавливает затронутый поток и зависимые пакеты; независимые потоки могут продолжать работу.

## Пакеты ревью

Ревьюер проверяет один интегрированный diff и общие сценарии на пакет, а не запускает отдельное ревью после каждой задачи. Отчёт исполнителя и статус `REVIEW` остаются у каждой задачи. Внутри одного прохода ревьюер фиксирует результат по каждому ID; отклонение одного ID не превращает остальные в автоматически принятые или отклонённые. Коммиты и перенос принятых задач выполняются по правилам статусов выше.

| Пакет | Состав | Когда начинать | Общая проверка |
| --- | --- | --- | --- |
| R1 · основа изображения | REL-12, REL-13, REL-01, REL-02, REL-03 | Все пять в `REVIEW`; интегрированы потоки A/B | Формат и UV-порядок, живые плоскости, геометрия/stride, BGRA gap, границы X/Y, revision и атомарная замена. |
| R2 · инициализация | REL-08, REL-09, REL-10 | R1 принят; весь поток C в `REVIEW` | Конкурентный запуск/повтор, точные IO/Web capabilities, каждый статус и атомарный отказ. |
| R3 · публичное поведение | REL-04, REL-05, REL-06, REL-07, REL-11 | R1/R2 приняты; потоки F/G/H интегрированы | Мутация против независимых результатов, legacy compile/UV, v2 golden и отказ v1, widget revision, IO/Web матрица. |
| R4 · выпуск и документы | REL-14, REL-15, REL-16 | R3 принят; metadata, SDK и тексты в `REVIEW` | Package/version/CHANGELOG, podspec, минимальный SDK, компилируемые примеры и описание миграции/Web. |
| R5 · финальная приёмка | REL-17, REL-18 | R3/R4 приняты; REL-17 в `REVIEW` | Итоговый SHA и платформенные gates; REL-18 проводит независимую оценку и фиксирует решение о готовности. |

Отдельный ревью-проход нужен при `REJECTED` только для исправленного пакета или затронутой им части следующего пакета. REL-18 не считается принятой автоматически после зелёных gates.


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

**Дополнено по итогам ревью R1 (2026-09-23):** явно включить в scope `@Deprecated` на `YuvFileFormat` и точки входа `nv21` (отложено из REL-01/03 намеренно, чтобы не плодить churn `deprecated_member_use_from_same_package` в ~9 файлах вне границ той задачи). Internal bridge-extensions `YuvPixelFormatLegacyBridge`/`YuvFileFormatPixelFormatBridge` (`lib/src/yuv/shared/yuv_pixel_format.dart`) — оставить unexported, это штатный механизм форвардинга для этой миграции, конфликта с планом депрекации нет (подтверждено Tier 1). Также добавить недостающий из REL-01 byte-level тест UV-порядка (запись/чтение реальных байт через `nv12`/`nv21`, round-trip через BGRA-конвертацию на native, плюс Web-аналог) — текущий тест сравнивает только stride/format, не байты.

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
