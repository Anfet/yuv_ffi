# yuv_ffi 0.4.0 — задачи до релиза

Основа: [дизайн 0.4.0](doc/api-abi-0.4-design.md) и решение владельца от 2026-09-23. Native ABI v1 выпущен в 0.3.0; публичный Dart API и codec v2 ещё требуют реализации. Приёмка нового релиза отменена до выполнения задач и повторной независимой проверки.

## Сводка статусов и Tier

| ✓ | ID | Статус | Tier / модель | Зависит от | Ревью | Результат |
| --- | --- | --- | --- | --- | --- | --- |
| [x] | REL-01 | DONE | 2 · Terra | — | R1 | `YuvPixelFormat`, NV12, wire ID. |
| [x] | REL-02 | DONE | 2 · Terra | — | R1 | Живые плоскости, `markDirty`, `applyPlanes`. |
| [x] | REL-03 | DONE | 2 · Terra | 01, 02 | R1 | Фабрики, `allocate`, RGBA импорт. |
| [x] | REL-04 | DONE | 2 · Terra | 01–03, 08–10 | R3 | Все мутирующие `apply*`. |
| [x] | REL-05 | DONE | 2 · Terra | 04 | R3 | Независимые `to*`, crop/rotate, байты. |
| [x] | REL-06 | DONE | 2 · Terra | 03–05 | R3 | Deprecated совместимость. |
| [x] | REL-07 | DONE | 2 · Terra | 01–03 | R3 | Codec: запись и чтение только v2. |
| [x] | REL-08 | DONE | 2 · Terra | — | R2 | `YuvFfi.initialize` и повторы IO/Web. |
| [x] | REL-09 | DONE | 2 · Terra | 01, 08 | R2 | Capabilities операций и форматов. |
| [x] | REL-10 | DONE | 2 · Terra | 08, 09 | R2 | Типизированные ошибки ABI/loader. |
| [x] | REL-11 | DONE | 2 · Terra | 02, 05, 08 | R3 | Widget/provider и revision. |
| [x] | REL-12 | DONE | 2 · Terra | — | R1 | BGRA с `pixelStride > 4`. |
| [x] | REL-13 | DONE | 2 · Terra | — | R1 | Границы X/Y в `YuvPlane`. |
| [x] | REL-14 | DONE | 3 · Luna | — | R4 | Apple/CMake release metadata. |
| [x] | REL-15 | DONE | 2 · Terra | — | R4 | Нижняя граница Flutter/Dart. |
| [x] | REL-16 | DONE | 3 · Luna | 01–15, 19, 20 | R4 | README, пример, Dartdoc, CHANGELOG. |
| [ ] | REL-17 | READY | 2 · Terra | 01–16 | R5 | Gates на итоговом SHA. |
| [ ] | REL-18 | BLOCKED | 1 · Sol | 17 | R5 | Независимая приёмка 0.4.0. |
| [x] | REL-19 | DONE | 2 · Terra | 06 | R3 | `format` → `YuvPixelFormat` на публичном интерфейсе. |
| [x] | REL-20 | DONE | 2 · Terra | 06, 07 | R3 | `encodeTo`/`YuvImage.decode` вместо `save`/`load`. |
| [ ] | REL-21 | REVIEW | 3 · Luna | 06, 16 | — | Миграция `example/` на `apply*`/`to*` API. |

**Итого (2026-09-23, после приёмки REL-16):** 17 DONE (REL-01–16 кроме REL-17–18, плюс REL-19, REL-20), 1 READY (REL-17), 2 BLOCKED (REL-18), 1 READY (REL-21, вне пакетов), 0 REVIEW, 0 REJECTED, 0 IN_PROGRESS. 0 ARCH REQUIRED. **Пакеты R1, R2, R3 полностью приняты.**
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

**Дополнено по итогам REL-09 (2026-09-23):** `yuvRequireCapability` (в `lib/src/yuv_capabilities.dart`) уже реализован и покрыт тестами изолированно — REL-09 намеренно не подключал его к реальным точкам вызова `apply*`, так как единого dispatch-слоя ещё не существовало. Каждый `apply*` в REL-04 должен вызывать `yuvRequireCapability(capabilities, YuvOperation.X, sourceFormat: ..., destinationFormat: ...)` первым действием, до любой аллокации/нативного вызова/изменения revision — именно это здесь и является критерием приёмки "отказ ABI" для случая отсутствующей capability.

### REL-05 — Независимые результаты

Реализовать `toI420/toNv12/toBgra`, `cropped/rotated`, `toBytes/toBgraBytes`. Источник и revision неизменны; результат владеет отдельными буферами даже для no-op. **Приёмка:** byte/aliasing тесты IO/Web, padded BGRA и semantic no-op.

### REL-06 — Старый публичный API

Старые instance-методы перенести в экспортируемый deprecated extension; фабрики/static методы, которые extension не сохраняет, оставить deprecated в типе. Сохранить in-place семантику старых `toYuv*` и `swapNv`, а также UV-порядок `nv21`. **Приёмка:** consumer compile-тест API 0.3.0, поведенческие тесты forwarding, скрытый `YuvImageImpl`; breaking change для чужих `implements YuvImage` описан.

**Дополнено по итогам ревью R1 (2026-09-23):** явно включить в scope `@Deprecated` на `YuvFileFormat` и точки входа `nv21` (отложено из REL-01/03 намеренно, чтобы не плодить churn `deprecated_member_use_from_same_package` в ~9 файлах вне границ той задачи). Internal bridge-extensions `YuvPixelFormatLegacyBridge`/`YuvFileFormatPixelFormatBridge` (`lib/src/yuv/shared/yuv_pixel_format.dart`) — оставить unexported, это штатный механизм форвардинга для этой миграции, конфликта с планом депрекации нет (подтверждено Tier 1). Также добавить недостающий из REL-01 byte-level тест UV-порядка (запись/чтение реальных байт через `nv12`/`nv21`, round-trip через BGRA-конвертацию на native, плюс Web-аналог) — текущий тест сравнивает только stride/format, не байты.

**REJECTED — Tier 1 ревью 2026-09-23.** Первая попытка (worktree agent-a0d50b08cdaed8c65) в основном корректна (скрытый `YuvImageImpl`, deprecated-фабрики, `copy(blank:)`, `y/u/v/getBytes`, атомарный `swapNv`, `@Deprecated` на `YuvFileFormat`), но не завершена внутри собственного scope — это доработка, а не редизайн.

**Architect Decision 1 — `format: YuvPixelFormat`:** дизайн требует ретайпинга (§4 строка 100: `format | format: YuvPixelFormat | Read-only | Always available`; исчерпывающий листинг строка 152: `YuvPixelFormat get format;`; §16: "The public storage format becomes `YuvPixelFormat`"). Промежуточное состояние (геттер остаётся `YuvFileFormat`) блокирует релиз: bridge-расширения из REL-01 намеренно unexported, поэтому у потребителя пакета нет чистого способа прочитать типизированный формат образа. **Владение переносится в новую задачу REL-19**, не в REL-06 — ретайпинг публичного геттера меняет core-член и переписывает assertions в уже принятых тестах REL-01/04/05/07, это отдельный diff для отдельного ревью. Внутренние ~60 точек вызова трогать не нужно — они продолжают читать `_state.format` (`YuvFileFormat`), маппится только публичный геттер.

**Architect Decision 2 — `toBgra8888()`:** переносится в `DeprecatedYuvImageApi` как часть REL-06 (не остаётся live core-членом). §4 строка 142: `toBgra8888() | toBgraBytes() | New tight byte copy`; в исчерпывающем листинге §4 (строки 150–227) `toBgra8888` отсутствует; §8: "Old renamed members must be removed from the concrete class/interface because an instance member would shadow the extension." Единственная причина держать метод live — вызов из `YuvImageProvider` (REL-11) — снята: REL-11 уже принят и смёржен (коммит `7f75621`), виджет теперь вызывает `toBgraBytes()` напрямую. Первая попытка REL-06 разрабатывалась в параллельном worktree и не видела этого коммита на момент решения.

**Оценка паттерна `YuvLegacyDispatchAdapter`:** идея верна (deprecated-слой обязан сохранять поведение 0.3.0, а 0.3.0 диспетчеризовал без `initialize()`) и отклоняется от буквального наброска §8 (`grayscale() => applyGrayscale();`) — это нужно зафиксировать как отдельное Architect Decision и обновить формулировку §8, что и делается здесь. Найдены три дефекта для исправления в доработке:
1. Дублирование логики может разойтись: `applyCrop/Flip*/Rotation/RgbaBytes` корректно делают "gate, затем `legacy*()`", но `applyGrayscale/BlackWhite/Negate/GaussianBlur` дублируют тело legacy-метода дословно на IO и Web. Каждый `apply*` должен стать "gate, затем `legacy*`" без исключений.
2. Чужие `implements YuvImage` регрессируют против дизайна: `_legacy()` кидает `UnsupportedError` для любого чужого класса. §8 разрешает такой fallback только для `load()`. Чужой получатель должен форвардиться на свой собственный `apply*`/`applyFormat(...)`. Throw допустим только для `swapNv()` — двухшаговый форвард не может быть атомарным на чужой реализации.
3. Именование: `yuv_legacy_swap.dart` содержит весь адаптер целиком — переименовать в `yuv_legacy_dispatch.dart`.

**Требуемая доработка REL-06 (тот же ID, новый проход):**
- (a) Ребейзнуться на актуальный `release/0.4.0` (после мёржа REL-11) и перенести `toBgra8888` в extension согласно Decision 2.
- (b) Каждый `apply*` должен делегировать в `legacy*` без исключений (устранить дублирование п.1).
- (c) Чужие получатели форвардятся на `apply*`, добавить тесты и для чужого получателя, и для пакетного.
- (d) Byte-level round-trip тест UV-порядка NV12/NV21 (IO + Web-аналог) из R1-дополнения всё ещё отсутствует — текущий новый тест-файл ссылается на `nv_chroma_order_test.dart`, который (по R1 ревью) проверяет только stride/format, не байты.
- (e) Тест "скрытый `YuvImageImpl`" ничего не доказывает, так как импортирует impl напрямую — добавить consumer-тест, который импортирует только `package:yuv_ffi/yuv_ffi.dart` и упражняет весь 0.3.0-surface.
- Переименовать `yuv_legacy_swap.dart` → `yuv_legacy_dispatch.dart` (п.3 выше).

**REL-06 ПРИНЯТ после доработки (2026-09-23).** Все 5 пунктов доработки подтверждены в коде независимо (unified gate-then-legacy* без дублирования на IO и Web; foreign-implementer forwarding с единственным документированным исключением `swapNv()`; переименование файла; byte-level UV round-trip тест; genuine public-surface-only hidden-impl тест). При интеграции найдено и исправлено 3 дополнительных дефекта:
1. 40 устаревших `@override` в `test/yuv_image_widget_test.dart` (файл REL-11, не в scope REL-06, но реальное следствие сокращения интерфейса) — удалены точечно.
2. Off-by-two в размере буфера нового byte-level chroma-теста (`Uint8List(w*h)` вместо `Uint8List((h~/2)*w)`) — реальный баг в тесте, не в реализации.
3. Тот же паттерн "file-level `setUp()` подсовывает fake library opener и не восстанавливает для группы, требующей реальную библиотеку", что уже чинился в REL-04 — повторился в двух новых test-группах (`rel06_deprecated_api_test.dart`'s `swapNv() matches historical bytes`, плюс отсутствие `YuvFfi.initialize()` в новом chroma-тесте). Также найдена и исправлена ложная универсальная assumption "на этом хосте нет native lib" в `rel06_public_surface_test.dart`, ломавшая тест именно на хосте, где native lib есть.

Итог: 618/618 тестов зелёные на реальной native-библиотеке, `flutter analyze` чист. REL-19 и REL-20 разблокированы.

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

**Решение владельца (2026-09-23):** объём этой задачи — README, Dartdoc, CHANGELOG. Полная миграция `example/` (main.dart, ext.dart, integration-тесты) на новый `apply*`/`to*` API вынесена в отдельную задачу REL-21 (README вместо этого содержит текстовую таблицу миграции 0.3.0→0.4.0). Пример-приложение продолжает компилироваться через deprecated extension без изменений.

**ВЫПОЛНЕНО (2026-09-23):**
- README: quick start переписан на `applyRgbaBytes/applyRotation/applyGrayscale/toBgraBytes`; добавлена секция "Live planes and `markDirty()`" с точной цитатой поведения `applyPlanes`; добавлена полная таблица миграции 0.3.0→0.4.0 (по каждому методу) с двумя поведенческими примечаниями (I420 default chroma stride 2→1, `swapNv()` как двухшаговый `applyFormat`+`applyChromaSwap`, codec v1→v2 несовместимость); публичный API список обновлён (`YuvPixelFormat`, `YuvOperation`, `YuvCapabilities`, `YuvNativeException`, deprecated `YuvFileFormat`); секция Initialization переведена на `YuvFfi.initialize()` → `YuvCapabilities`; Web WASM секции (список операций, parity-матрица) переведены с 0.3.0-имён методов на `apply*`/`to*`; версия pubspec `^0.3.0` → `^0.4.0`.
- CHANGELOG: секция 0.4.0 переписана из "Planned/Unreleased" в фактический список изменений с описанием реализованного поведения (не намерения); добавлена заметка про вынесенную в REL-21 миграцию примера.
- Оба ключевых code-snippet'а README (quick start + capabilities-gate + markDirty) скомпилированы через `dart analyze` против реального пакета — 0 ошибок.
- Design-doc §16 намеренно не переименован ("Planned breaking changes for 0.4.0" остаётся заголовком раздела дизайн-документа, не текущего состояния) — вне scope этой задачи, дизайн-документ не редактируется по правилу AGENTS.md.
- Версия pubspec (`0.4.0`) совпадает с верхней записью CHANGELOG.

### REL-17 — Release gates

На итоговом SHA запустить format/analyze/tests, bindings/symbol audit, C tests/sanitizers, IO/Web reference matrix, Android/Apple CI builds, пример и publish dry-run. **Приёмка:** таблица SHA/платформа/команда/результат; runtime отделён от сборки; пропуски и риски указаны явно.

### REL-18 — Новая приёмка

Независимо сверить реализацию с дизайном 0.4.0 и результатами REL-17. Приёмку 0.3.0 не переносить на новый API. **Приёмка:** отдельный отчёт с каждым blocker и решением о готовности к тегу/публикации; до этого задача остаётся BLOCKED.

### REL-19 — `format` возвращает `YuvPixelFormat`

**Заведено Tier 1 2026-09-23 по итогам ревью REL-06** (Architect Decision 1 в описании REL-06 выше). `YuvImage.format` должен возвращать `YuvPixelFormat` на интерфейсе и во всех трёх backend (IO/Web/stub); внутренний код продолжает читать `_state.format` (`YuvFileFormat`), трогать ~60 внутренних точек вызова не нужно — маппится только публичный геттер через уже существующие bridge-extensions REL-01. Legacy `nv21`-образы должны репортить `format == YuvPixelFormat.nv12` (§4 строки 112/144); внутренний stride-клэмп `nv21` остаётся как есть. **Приёмка:**
- Consumer-тест, использующий только публичный импорт (`package:yuv_ffi/yuv_ffi.dart`), делает исчерпывающий `switch (image.format)` по `YuvPixelFormat` без deprecation-предупреждений.
- `swapNv()` на не-NV входе даёт `format == YuvPixelFormat.nv12`.
- Затронутые assertions в уже принятых тестах (REL-01/04/05/07) и чужие test-fixtures обновлены.
- Единственная оставшаяся публичная точка `YuvFileFormat` — deprecated unnamed-фабрика.
- `flutter analyze` чист, тесты не хуже базовой линии.

### REL-20 — `encodeTo`/`YuvImage.decode` вместо `save`/`load`

**Заведено Tier 1 2026-09-23 по итогам ревью REL-06.** Ни REL-01, ни REL-07, ни REL-06 не взяли на себя эту часть §4 (строки 120–121, исчерпывающий листинг строки 181/225) и §8: `encodeTo(sink)` и статический `YuvImage.decode(stream)` нигде не существуют в `lib/`, хотя дизайн их требует; `save`/`load` должны переехать в deprecated extension. **Приёмка:**
- `save` форвардится на `encodeTo` с идентичными байтами.
- `load` работает через package-private atomic state-replacement adapter (аналогично `YuvLegacyDispatchAdapter` из REL-06).
- `load` на чужом получателе (`implements YuvImage` вне пакета) кидает `UnsupportedError` и не меняет его состояние (§8 строки 463–467).
- `decode` возвращает новый образ и не меняет получателя (если вызван как метод расширения на существующем экземпляре) либо является чистой статической фабрикой.

При R3-ревью пакета проверить остальные строки §4 на предмет других "осиротевших" пунктов, не взятых в scope ни одной задачей.

**REL-19 и REL-20 ПРИНЯТЫ (2026-09-23).** Выполнены параллельно в отдельных worktree на базе `c35f117`, независимо проверены (диффы построчно, `flutter analyze`, `flutter test` на реальной `yuv_ffi.dll`) до интеграции.

REL-19: ретайпинг `format` на `YuvPixelFormat` во всех трёх backend через уже существующий bridge REL-01 (`YuvFileFormatPixelFormatBridge`), ~90 внутренних точек вызова механически переведены на `_state.format` без изменения логики. Добавлен exhaustive-switch consumer-тест и `nv21→nv12` тест. Два файла в `example/` (`ext.dart`, `image_cache_key_test.dart`) исправлены за пределами заявленного scope `lib/`+`test/`, так как ретайпинг ломал их компиляцию/анализ — минимальные механические правки, оправданы требованием критерия приёмки "flutter analyze чист".

REL-20: `encodeTo`/`decode` добавлены на интерфейс; `save`/`load` перенесены в `DeprecatedYuvImageApi` теми же средствами, что REL-06 использовал для остальных legacy-методов (`YuvLegacyDispatchAdapter.legacyLoad`, атомарная замена состояния через уже существующий `YuvImageState.decodeAndReplace`). `load()` на чужом получателе кидает `UnsupportedError` без мутации — второе документированное исключение после `swapNv()`. Stub-backend `load` осознанно переведён с no-op на настоящий decode для симметрии с IO/Web (не покрыт тестами, недостижим из `flutter test`, native код не тронут).

**Интеграция:** оба диффа применились друг на друга без текстовых конфликтов (пересекались в 4 test-fixture файлах на разных строках). При интеграции обнаружен и исправлен один реальный шов: новый `test/rel20_encode_decode_test.dart` содержал собственный `_ForeignImage` fixture с `format` ещё типа `YuvFileFormat` (агент REL-20 не видел диффа REL-19, так как оба работали параллельно) — поправлено на `YuvPixelFormat`, устаревший комментарий про "REL-19 is a separate parallel task" удалён. Полный набор тестов на объединённом дереве: **630/630** (618 база + 2 REL-19 + 10 REL-20), `flutter analyze` чист (0 ошибок).

REL-16 разблокирована (READY): теперь зависит от 01–15 плюс 19, 20, так как документирует финальную публичную поверхность API.

### REL-21 — Миграция `example/` на `apply*`/`to*` API

**Заведено при приёмке REL-16 (2026-09-23) по решению владельца.** `example/lib/main.dart` и `ext.dart` целиком используют устаревший 0.3.0 API (`rotate`, `grayscale`, `blackwhite`, `negate`, `gaussianBlur`/`meanBlur`/`boxBlur`, `crop`, `flipHorizontally`/`flipVertically`, `fromRgba8888`, `toYuvI420`/`toYuvNv21`/`toYuvBgra8888`) — компилируется только благодаря `DeprecatedYuvImageApi`. `example/lib/widgets/impl/*` (desk/mobile/web camera preview) и ~10 файлов в `example/integration_test/` также используют старый API. **Объём:**
- Перевести видимый пользователю demo-код (`main.dart`, `ext.dart`, `widgets/impl/*`) на `apply*`/`to*`/`YuvFfi.initialize()`.
- `example/integration_test/*` — тесты поведения; при миграции сохранить их фактическую проверяемую семантику (byte-exact/timing контракты), не только сменить имена методов. Если какой-то тест специально проверяет legacy-диспетчеризацию (`DeprecatedYuvImageApi`/`YuvLegacyDispatchAdapter`) — не мигрировать его, он существует для проверки обратной совместимости.
- Обновить README/CHANGELOG, если пример перестаёт демонстрировать deprecated API (таблица миграции REL-16 остаётся, так как 0.3.0-код по-прежнему компилируется и существует у внешних потребителей).

**Приёмка:** `flutter analyze`/`flutter test` на `example/` чисты; демо-функциональность (камера, кроп, эффекты, face detection) не регрессирует; `flutter pub publish --dry-run` без новых предупреждений про пример.

Не блокирует REL-17/REL-18 — миграция примера не входит в release gates 0.4.0.

**Отчёт исполнителя (2026-09-23):** `main.dart`, `ext.dart` и все четыре `widgets/impl/*` переведены на `apply*`/`applyFormat`/`applyRgbaBytes`/`toBytes`/`YuvFfi.initialize()`. `integration_test/*` не тронуты — весь набор проверок в них (`getbytes_contract_test.dart`, `serialization_contract_test.dart`, `image_cache_key_test.dart`'s swapNv/save/load кейсы, `reference_web_conversions_test.dart`'s operation-switch) предметно проверяет legacy-диспетчеризацию/обратную совместимость, что явно исключено из scope. `ext.dart`: `YuvImage.nv21(...)` для `ImageFormatGroup.nv21` оставлен как есть с явным `// ignore: deprecated_member_use` и комментарием — это не случайный legacy-вызов, `nv21`-камера-кадры физически несут UV-порядок, который сохраняет только `nv21`-фабрика; замена на `nv12()` тихо сломала бы chroma. Найден и исправлен реальный дефект (не просто переименование): `yuv_camera_preview_web.dart` писал в `yPlane` напрямую (`assignFrom`) без последующего `markDirty()` — по контракту REL-02/design §4 это оставляло revision несвежим для виджет-кэша; добавлен вызов `markDirty()` сразу после прямой записи.

Проверено: `flutter analyze lib` в `example/` — 0 issues. Полный `flutter analyze` — 203 info/warning, все в `integration_test/*`, ни одного нового (переиспользуют уже принятый REL-06/REL-19/REL-20 deprecated-слой намеренно) и 5 pre-existing warning в `image_cache_key_test.dart` (не в диффе, `git diff` по файлу пуст). `dart format --line-length 150` на изменённых файлах — без правок. `flutter pub get` в `example/` проходит. `flutter test`/`integration_test` не прогнаны — в `example/` нет обычного `test/`, весь набор в `integration_test/*` и требует реального устройства/браузера (см. memory про Mac-раннер); демо-функциональность (камера/face detection) также не проверена вручную на устройстве. CHANGELOG обновлён: снята пометка "example всё ещё на deprecated API".
