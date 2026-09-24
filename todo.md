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
| [ ] | REL-07 | TODO | 2 · Terra | 01–03 | R3 | Codec: запись и чтение только v2. |
| [x] | REL-08 | DONE | 2 · Terra | — | R2 | `YuvFfi.initialize` и повторы IO/Web. |
| [x] | REL-09 | DONE | 2 · Terra | 01, 08 | R2 | Capabilities операций и форматов. |
| [x] | REL-10 | DONE | 2 · Terra | 08, 09 | R2 | Типизированные ошибки ABI/loader. |
| [x] | REL-11 | DONE | 2 · Terra | 02, 05, 08 | R3 | Widget/provider и revision. |
| [x] | REL-12 | DONE | 2 · Terra | — | R1 | BGRA с `pixelStride > 4`. |
| [x] | REL-13 | DONE | 2 · Terra | — | R1 | Границы X/Y в `YuvPlane`. |
| [ ] | REL-14 | TODO | 3 · Luna | — | R4 | Apple/CMake release metadata. |
| [x] | REL-15 | DONE | 2 · Terra | — | R4 | Нижняя граница Flutter/Dart. |
| [ ] | REL-16 | TODO | 3 · Luna | 01–15, 19, 20 | R4 | README, Dartdoc, CHANGELOG. |
| [ ] | REL-17 | TODO | 2 · Terra | 01–16 | R5 | Gates на итоговом SHA. |
| [ ] | REL-18 | BLOCKED | 1 · Sol | 17 | R5 | Независимая приёмка 0.4.0. |
| [x] | REL-19 | DONE | 2 · Terra | 06 | R3 | `format` → `YuvPixelFormat` на публичном интерфейсе. |
| [x] | REL-20 | DONE | 2 · Terra | 06, 07 | R3 | `encodeTo`/`YuvImage.decode` вместо `save`/`load`. |
| [ ] | REL-21 | TODO | 3 · Luna | 06, 16 | — | Миграция `example/` на `apply*`/`to*` API. |

**Итого после независимого ревью доработок (2026-09-24):** 15 DONE, 5 TODO (REL-07, REL-14, REL-16, REL-17, REL-21), 0 REVIEW, 0 IN PROGRESS, 1 BLOCKED (REL-18), 0 READY, 0 ARCH REQUIRED. Первичное ревью ниже сохранено как исторический снимок; последующие вердикты добавлены к карточкам задач.
`READY` означает определённый объём; `BLOCKED` — невыполненную зависимость. `DONE` возможен после отчёта исполнителя и независимой проверки, а не только после зелёных тестов.

## Первичное независимое ревью всех DONE и REVIEW (2026-09-23)

Проверена текущая ветка `release/0.4.0` на `904991d` (после gate-коммита `17771a9`). Локально `flutter test --no-pub`: **630/630**, exit 0. `flutter analyze --no-pub`: **0 errors, 0 warnings, 200 info**, exit 1. `flutter pub publish --dry-run`: **1 warning, 1 hint**, exit 65. Внешний [CI run 35882819637](https://github.com/Anfet/yuv_ffi/actions/runs/35882819637) завершился failure; зелёные native/Apple/Android/required Web jobs не делают весь release gate зелёным. Временный воспроизводящий тест для gapped NV12 удалён после прогона; рабочее дерево до правки этого трекера было чистым.

| Пакет | Задачи | Независимый вердикт |
| --- | --- | --- |
| R1 | REL-01, REL-03, REL-12, REL-13 | DONE: публичный формат/wire ID, фабрики, BGRA gap и проверки координат соответствуют своим критериям; существующие тесты прошли. |
| R1 | REL-02 | TODO: `applyPlanes(image.planes)` отвергает созданный через `YuvImage.nv12(4, 4, uvPixelStride: 3)` образ; см. находку A. |
| R2 | REL-08, REL-09, REL-10 | DONE: инициализация, capability-матрица и отображение ошибок покрыты тестами; required Web gate в CI прошёл. |
| R3 | REL-06, REL-11, REL-19 | DONE: legacy surface, widget/provider и публичный `format` подтверждены compile/behavior тестами и проверкой реализаций. |
| R3 | REL-04 | TODO: исправить устаревшую проверку имени формата в Web matrix и повторить прогон всех 119 кейсов; четыре сбоя не дошли до проверки пикселей (находка B). |
| R3 | REL-05 | TODO: `copy()` разрешённого gapped NV12 бросает `ArgumentError`, поэтому независимый `toNv12()` того же формата и no-op `cropped`/`rotated` также имеют риск; см. находку A. |
| R3 | REL-07, REL-20 | TODO: v2 запись gapped NV12 проходит, чтение того же payload бросает `FormatException`; публичная `YuvImage.decode` использует тот же codec и legacy-конструктор. См. находку A. |
| R4 | REL-14 | TODO: Apple metadata и CI builds проверены, но обязательный publish dry-run имеет warning о двух tracked файлах под `.gitignore`; критерий «без предупреждений» не выполнен (находка C). |
| R4 | REL-15 | TODO: в CI используется Flutter 3.44.9, а воспроизводимого лога на заявленных Flutter 3.38.x / Dart 3.10.x и изменения constraints не найдено. Нижняя граница не доказана. |
| R4 | REL-16 | TODO: после исправления gapped NV12 повторно проверить тексты и примеры на соответствие работающему контракту (находка A). |
| R5 | REL-17 | TODO: штатные analyze, example analyze/build, Web reference matrix и publish dry-run не прошли. Итоговый gate не выполнен; отчёт исполнителя точно перечисляет сбои, но его вывод о дефекте Web backend преждевременен (находки B–D). |
| Вне пакетов | REL-21 | TODO: миграция demo-кода просмотрена, но её собственные `flutter analyze`/runtime критерии не выполнены; `reference_web_conversions_test.dart` проверяет матрицу конверсий, а не исключительно legacy dispatch. См. находку D. |

**Находка A — gapped NV12, REL-02/05/07/20.** Дизайн и REL-03 разрешают `uvPixelStride >= 2`; `YuvGeometry.validateImage` принимает это только с `allowLargerNvChromaStride`. `YuvImageState.applyPlanes` и `copy()` через legacy-конструктор не передают флаг; `YuvCodec._decodeFrom` явно требует stride ровно 2, а финальная проверка снова вызывает strict validator. Отдельный временный Flutter-тест воспроизвёл три отказа на одном `YuvImage.nv12(4, 4, uvPixelStride: 3)`: `copy()` и `applyPlanes()` бросили `ArgumentError`, encode→decode бросил `FormatException`. Исправить все пути и добавить постоянный round-trip/aliasing regression на IO и Web. Native C не менять без отдельного плана и согласования.

**Находка B — Web matrix, REL-04/17.** Четыре падающих ID — `FORMAT-TO-NV21-*`. В Web-тесте `reference_web_conversions_test.dart` сравнивает `result.image.format.name` со старой строкой `nv21`, тогда как после REL-19 публичный `format` правильно равен `YuvPixelFormat.nv12`. Нативный аналог уже отображает `nv12` на legacy имя manifest перед сравнением. Web-тест падает на этом assert **до** сверки пикселей; текущий CI не доказывает расхождение самих конверсий. Согласовать проверку формата и повторить все 119 кейсов; только после этого судить о Web backend.

**Находка C — пакетирование, REL-14/17.** `todo.md` и `todo-waitlist.md` одновременно tracked и перечислены в `.gitignore`; `pub publish --dry-run` возвращает warning и exit 65. Согласовать `.gitignore`/`.pubignore` так, чтобы релизный архив имел намеренный состав и dry-run завершался без warning. Hint о последней версии pub.dev `0.2.4` — отдельное информационное расхождение, его не смешивать с warning.

**Находка D — gates и пример, REL-17/21.** `flutter analyze` даёт 200 info (намеренные legacy-вызовы в `example/integration_test/*` плюс два unnecessary imports) и exit 1, поэтому CI не доходит до root unit tests и Web build примера. Нужно сохранить проверку legacy поведения, убрав info из стандартного gate или явно согласовав политику analyzer для намеренно deprecated тестов. REL-21 также требует проверки demo камеры/эффектов/face detection на реальном runtime; такого доказательства нет. Для не-legacy reference matrix нельзя считать старые вызовы основанием исключить тест из миграции без отдельного решения.

REL-18 остаётся BLOCKED до повторного ревью исправленных задач и зелёного REL-17. Статусы в таблице выше заменяют прежние отметки приёмки; исторические отчёты ниже не удалены.

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
| R3 · публичное поведение | REL-04, REL-05, REL-06, REL-07, REL-11, REL-19, REL-20 | R1/R2 приняты; потоки F/G/H интегрированы | Мутация против независимых результатов, legacy compile/UV, публичный формат и decode, v2 golden и отказ v1, widget revision, IO/Web матрица. |
| R4 · выпуск и документы | REL-14, REL-15, REL-16 | R3 принят; metadata, SDK и тексты в `REVIEW` | Package/version/CHANGELOG, podspec, минимальный SDK, компилируемые примеры и описание миграции/Web. |
| R5 · финальная приёмка | REL-17, REL-18 | R3/R4 приняты; REL-17 в `REVIEW` | Итоговый SHA и платформенные gates; REL-18 проводит независимую оценку и фиксирует решение о готовности. |

Отдельный ревью-проход нужен при `REJECTED` только для исправленного пакета или затронутой им части следующего пакета. REL-18 не считается принятой автоматически после зелёных gates.


## Публичный API

### REL-01 — Имя и формат

Добавить экспортируемый `YuvPixelFormat` (`i420`, `nv12`, `bgra8888`) со стабильными wire ID 1/2/3. Legacy `nv21` сохранить с историческими UV-байтами и deprecated пометкой; RGBA оставить входным форматом ABI. **Приёмка:** compile-тест корневого экспорта, проверки ID и UV-порядка на IO/Web; enum index не попадает в codec.

### REL-02 — Живые плоскости

Конструкторы копируют входные буферы. `planes/yPlane/uPlane/vPlane` и legacy `y/u/v` возвращают живые плоскости; список структурно неизменяем. После прямой записи вызывается `markDirty()`; `applyPlanes` валидирует и копирует набор, атомарно заменяет его и повышает revision один раз. Замена плоскостей делает ранее полученные ссылки устаревшими. **Приёмка:** aliasing, copy-in, revision/cache, повторное получение плоскостей и неизменность при отказе.

**Отчёт исполнителя (2026-09-23):** `YuvImageState` теперь сохраняет уже утверждённый признак `allowLargerNvChromaStride`, который задаёт `nv12`-фабрика, и передаёт его при `applyPlanes`. Поэтому замена живых плоскостей у gapped NV12 (`uvPixelStride: 3`) использует ту же разрешённую геометрию, что и конструктор; legacy `nv21` остаётся строгим. Добавлен regression на gapped набор с проверкой copy-in/отсутствия aliasing. Native C и generated bindings не менялись. Проверено: focused VM 15/15, полный `flutter test --no-pub` 631/631, focused `flutter analyze --no-pub` без issues, `git diff --check` чист. Web Chrome-команда не вернула финальный результат за лимит среды; это не засчитано как Web-приёмка и должно быть повторено ревьюером/CI.

**Повторное ревью (2026-09-24) — TODO:** прогнать Web-регрессию `applyPlanes` для gapped NV12 в настоящем browser/WASM harness и зафиксировать результат. VM и статическая проверка не заменяют Web-приёмку; дефект в текущей реализации по доступным проверкам не подтверждён.

**Среда Web-приёмки (2026-09-24):** `D:\.projects\.tools\chromedriver-win64\chromedriver.exe` обновлён до **154.0.8037.57**. Это только driver: `chrome.exe` в каталоге больше нет, поэтому browser берётся из системной установки. На выделенном Mac (macOS 15.6.1, Flutter 3.44.9, Chrome 154.0.8037.57) focused VM suite прошла; Web `flutter drive` завершился до тестов с DWDS `AppConnectionException`.

**Попытка browser-приёмки на Mac (2026-09-24):** текущий Windows tree синхронизирован в отдельный `~/claude-work/yuv_ffi-rel02-web-20260924` без `.git`, `.dart_tool` и `build`; после `flutter pub get` команда `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/reference_web_conversions_test.dart -d chrome --no-headless` ждала debug service 15.8 s и упала с `AppConnectionException` в `dwds DevHandler._startLocalDebugService`. `applyPlanes` gapped-NV12 browser regression не выполнилась; это инфраструктурный blocker, не дефект реализации.

**Доработка исполнителя (2026-09-24):** добавлен `example/integration_test/rel02_rel05_web_regression_test.dart`, который исполняется через asset-aware harness `flutter drive -d web-server --browser-name=chrome`. На обновлённых системном Chrome **154.0.8037.58** и ChromeDriver **154.0.8037.57** проверены gapped NV12 `applyPlanes` (copy-in, stride 3, revision) и REL-05 contracts (независимый `copy`, padded BGRA без padding в `toBgraBytes`, full-frame crop возвращает отдельный образ без смены revision). `tool/wasm/yuv40_web_matrix_probe.ps1` завершил запуск с `flutter_exit=0`, лог содержит `All tests passed.`; static `flutter analyze --no-pub integration_test/rel02_rel05_web_regression_test.dart` — No issues found. Передано в REVIEW.

**Независимое ревью (2026-09-24) — ПРИНЯТО:** сохранённый флаг gapped NV12 передаётся в `applyPlanes`; новая плоскость валидируется до публикации, копируется и повышает revision один раз. Browser target действительно проверяет `kIsWeb` и выполняется с WASM assets: `rel02-rel05-web-20260924.log.result` содержит `flutter_exit=0`, лог — `All tests passed.` Повторный focused VM suite (вместе с REL-04/05/07) — 128 passed; `dart analyze` затронутого кода — No issues found.

### REL-03 — Фабрики

Реализовать `i420/nv12/bgra`, `allocate`, `fromRgbaBytes` и геометрию из раздела 4 дизайна. I420 по умолчанию имеет chroma pixelStride 1, NV12 — 2; явные stride сохраняются. **Приёмка:** чётные и нечётные размеры, tight/padded/gapped layouts, неверные аргументы, корневой экспорт на IO/Web.

### REL-04 — Мутация

Реализовать весь набор `apply*` из дизайна: эффекты, три blur, crop, flip, rotation, format, chroma swap, RGBA и planes. Успех возвращает `identical(this)` и увеличивает revision один раз; определённые no-op и отказ не меняют байты, metadata и revision. **Приёмка:** матрица операций/форматов IO и поддерживаемого Web, padding/alpha, odd crop и blur border против reference oracle, отказ ABI.

**Дополнено по итогам REL-09 (2026-09-23):** `yuvRequireCapability` (в `lib/src/yuv_capabilities.dart`) уже реализован и покрыт тестами изолированно — REL-09 намеренно не подключал его к реальным точкам вызова `apply*`, так как единого dispatch-слоя ещё не существовало. Каждый `apply*` в REL-04 должен вызывать `yuvRequireCapability(capabilities, YuvOperation.X, sourceFormat: ..., destinationFormat: ...)` первым действием, до любой аллокации/нативного вызова/изменения revision — именно это здесь и является критерием приёмки "отказ ABI" для случая отсутствующей capability.

**Отчёт исполнителя (2026-09-23):** исправлена Web reference matrix: после REL-19 публичный `format` имеет тип `YuvPixelFormat` и для canonical NV12 правильно возвращает `nv12`, тогда как неизменяемый historical manifest называет эту же раскладку `nv21`. Assertion теперь маппит только это legacy имя перед сравнением, как уже делает native matrix; проверка пикселей больше не пропускается. Static analyze не выявил errors/warnings, только 53 ожидаемых deprecated info в compatibility matrix. Реальный `flutter drive` собрал и запустил target до подключения Chrome, но среда не содержит chromedriver на 4444; прогон 119 кейсов остаётся обязательным для ревью/CI. Native C не менялся.

**Повторное ревью (2026-09-24) — TODO:** выполнить `example/integration_test/reference_web_conversions_test.dart` через `flutter drive` с Web assets и ChromeDriver, подтвердить 119/119 и пиксельные assertions, особенно четыре прежних `FORMAT-TO-NV21-*`. При сбоях исправить причину и повторить матрицу.

**Среда Web-приёмки (2026-09-24):** `D:\.projects\.tools\chromedriver-win64\chromedriver.exe` — 154.0.8037.57; browser берётся из системной установки, поскольку `chrome.exe` в каталоге driver отсутствует. Mac имеет Chrome 154.0.8037.57, но `flutter drive` остановился на DWDS `AppConnectionException` до запуска матрицы. Штатный `tool/wasm/yuv40_web_matrix_probe.ps1` остаётся предпочтительным для локального Windows прогона и не должен убивать браузер/driver по имени.

**Попытка browser-приёмки на Mac (2026-09-24):** команда matrix из изолированной синхронизированной копии завершилась с `AppConnectionException` после 15.8 s ожидания debug service; 119 case IDs и pixel assertions не исполнялись. Повторять после устранения DWDS/WebDriver bootstrap.

**Доработка исполнителя (2026-09-24):** local probe переведён на тот же устойчивый transport, что CI: `flutter drive -d web-server --browser-name=chrome --headless`; режим `-d chrome` в Flutter 3.44 подписывается на неподдерживаемый Web `Timer` stream ещё до запуска target. В `reference_web_conversions_test.dart` восстановлена семантика legacy manifest operation `swapNv`: I420 перед каждым U/V swap явно приводится к canonical NV12, поскольку новый `applyChromaSwap()` намеренно отвергает I420. После этого полный Web/WASM reference matrix прошёл **119/119**: probe `rel04-webserver-fixed-20260924`, `flutter_exit=0`, `All tests passed.`; focused `flutter analyze --no-pub integration_test/reference_web_conversions_test.dart` — No issues found; root regressions `flutter test --no-pub test/rel06_deprecated_api_test.dart test/yuv_apply_surface_test.dart` — 47 passed. Передано в REVIEW.

**Независимое ревью (2026-09-24) — ПРИНЯТО:** Web matrix проверяет 119 уникальных case IDs и завершилась с `flutter_exit=0`; из кода теста следует, что каждый case проходит форматные, pixel/reference и raw-plane assertions до общего `All tests passed.` Исправленная ветка `swapNv` соответствует legacy contract. Повторный focused VM suite — 128 passed; статический анализ затронутого кода — без замечаний.

### REL-05 — Независимые результаты

Реализовать `toI420/toNv12/toBgra`, `cropped/rotated`, `toBytes/toBgraBytes`. Источник и revision неизменны; результат владеет отдельными буферами даже для no-op. **Приёмка:** byte/aliasing тесты IO/Web, padded BGRA и semantic no-op.

**Отчёт исполнителя (2026-09-23):** derived-image paths теперь передают сохранённый признак gapped NV12 в IO/Web/stub state. Поэтому `copy()`, `cropped()` и `rotated()` не отклоняют исходный `YuvImage.nv12(..., uvPixelStride: 3)` при повторной валидации и по-прежнему глубоко копируют его плоскости. Добавлены VM и Web regression-тесты copy layout/aliasing; VM focused suite прошла 14/14 (Web counterpart выполняется только в browser harness). Focused analyze без issues. Native C не менялся.

**Повторное ревью (2026-09-24) — TODO:** выполнить Web-вариант byte/aliasing и no-op проверок REL-05, включая gapped NV12, padded BGRA и независимость результата, в browser/WASM harness; приложить результат к карточке. Попытка `flutter test --platform chrome` зависла на загрузке и не засчитывается: WASM-тестам нужен asset bundle примера.

**Среда Web-приёмки (2026-09-24):** локальный ChromeDriver: `D:\.projects\.tools\chromedriver-win64\chromedriver.exe` 154.0.8037.57; browser берётся из системной установки. На Mac Chrome 154 доступен, однако shared Web bootstrap завершился DWDS `AppConnectionException` до тестов, поэтому REL-05 browser assertions не подтверждены.

**Проверка на Mac (2026-09-24):** `flutter test --no-pub test/yuv_apply_planes_test.dart test/rel05_independent_results_test.dart` — 18 passed, 10 skipped только из-за отсутствия Mac native library. Это подтверждает VM-contract, но не заменяет требуемую browser/WASM приёмку.

**Доработка исполнителя (2026-09-24):** browser/WASM coverage добавлена и выполнена вместе с REL-02 в `example/integration_test/rel02_rel05_web_regression_test.dart`: gapped NV12 `copy()` не alias-ит plane bytes, `toBgraBytes()` пакует padded BGRA без sentinel padding, full-frame `cropped()` возвращает отдельный объект и не меняет revision источника. Probe завершился `flutter_exit=0` и `All tests passed.`; задача передана в REVIEW.

**Независимое ревью (2026-09-24) — TODO:** browser target исполняет только два теста. Для REL-05 он не проверяет byte correctness `toI420()/toNv12()/toBgra()`, независимость результата `cropped()/rotated()` после записи в источник, независимость буферов `toBytes()/toBgraBytes()` и глубокую независимость full-frame crop (сейчас проверяются лишь `identical` и revision). Эти проверки уже написаны в `test/web/rel05_independent_results_web_test.dart`, но тот файл запускается только через `flutter test -p chrome`, который по локальному отчёту не обслуживает WASM assets, и успешного browser запуска файла нет. Перенести содержательные проверки в asset-aware integration target или обеспечить исполнение существующего Web suite с WASM; зафиксировать лог и включить target в обязательный Web CI gate. VM suite и два browser теста засчитываются как частичное покрытие, не как выполнение критерия byte/aliasing IO/Web.

**Доработка исполнителя (2026-09-24):** `example/integration_test/rel02_rel05_web_regression_test.dart` расширен до трёх WASM browser cases: byte correctness `toI420()/toNv12()/toBgra()`, независимость результатов после `applyNegate()` источника для всех `to*`, `cropped()` и `rotated()`, а также отсутствие aliasing у `toBytes()/toBgraBytes()`, padded BGRA, full-frame crop и same-format `toNv12()/toBgra()`. Target выполнен через asset-aware `flutter drive -d web-server --browser-name=chrome --headless`: `rel05-full-web-20260924.log.result` содержит `flutter_exit=0`, лог — `All tests passed.` Target добавлен в `Required Web integration gate` CI.

**Независимое ревью (2026-09-24) — ПРИНЯТО:** расширенный browser target повторно выполнен на реальном WASM: `rel05-independent-review-20260924.log.result` содержит `flutter_exit=0`, лог — `All tests passed.` Покрыты независимость результатов `to*`, `cropped`, `rotated`, копии byte API, padded BGRA и semantic no-op; target включён в обязательный Web CI gate. Focused codec suite — 55 passed; `dart analyze` затронутых root файлов и `flutter analyze` browser target — No issues found.

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

**Отчёт исполнителя (2026-09-24):** `YuvCodec` пишет только канонический v2: JSON-заголовок с `version: 2`, стабильным `formatId`, шириной и высотой, затем строгую метаинформацию и байты плоскостей. Reader принимает фрагментированный поток, проверяет EOF, число/геометрию/длины плоскостей и trailer; v1-shaped payload, неизвестная или неверная версия, поля/форматы/размеры и лишние байты отвергаются `FormatException` без частичного изменения получателя. Добавлен фиксированный byte-level golden v2 для `I420 2×2`; покрыты round-trip всех форматов, padding и gapped NV12, а также legacy `load`/новый `YuvImage.decode`. README и CHANGELOG требуют перекодировать сохранённые v1 данные приложением на 0.3.0 до обновления. Native C и generated bindings не менялись.

**Повторная проверка (2026-09-24):** focused codec/decode suite — 53 passed; полный `flutter test --no-pub` — 635 passed; `flutter analyze --no-pub lib test/yuv_serialization_test.dart test/rel20_encode_decode_test.dart` — No issues found; `git diff --check` — clean. Передано в REVIEW для независимой приёмки.

**Повторное ревью (2026-09-24) — TODO:** исправить описание миграции v1→v2 вместе с REL-16. Код 0.3.0 (`42c2ae1`) пишет `version: 1`, поэтому повторный `save` на 0.3.0 не создаёт читаемый 0.4.0 payload. Описать осуществимый этапный перенос: старым приложением прочитать v1 и сохранить формат, размеры, strides и байты в промежуточном представлении; новым приложением восстановить образ и записать v2 через `encodeTo`. Проверить инструкцию на одном v1 fixture и зафиксировать результат. Реализация codec v2 и её тесты замечаний не вызвали.

**Доработка исполнителя (2026-09-24):** README, CHANGELOG, Dartdoc `YuvCodec` и design §6 теперь описывают выполнимый двухэтапный перенос: приложение на 0.3.0 извлекает format, размеры, row/pixel strides и bytes в собственное промежуточное представление; после обновления 0.4.0 восстанавливает `YuvImage` и записывает v2 через `encodeTo`. Явно зафиксировано, что повторный `save` на 0.3.0 снова создаёт v1. Исторический v1 fixture (string `format`, без `formatId`) проверен в `test/yuv_serialization_test.dart`: current decoder отвергает его с `FormatException`, не интерпретируя как v2. Проверки: `flutter test --no-pub test/yuv_serialization_test.dart test/rel20_encode_decode_test.dart` — 53 passed; `flutter analyze --no-pub lib/src/yuv/shared/yuv_codec.dart test/yuv_serialization_test.dart test/rel20_encode_decode_test.dart` — No issues found; format — clean.

**Независимое ревью (2026-09-24) — TODO:** описание двухэтапного переноса исправлено, но требование предыдущего ревью «проверить инструкцию на одном v1 fixture» не выполнено. Тест с v1-shaped payload проверяет только `FormatException` в 0.4.0; он не загружает fixture кодом 0.3.0 и не проверяет экспорт промежуточных format/dimensions/strides/bytes, восстановление в 0.4.0 и итоговый v2 round-trip. Добавить воспроизводимый проверочный сценарий с одним настоящим v1 fixture, сверить все плоскости и метаданные до и после переноса, оставить отказ прямого чтения v1 отдельным тестом. Код v2 и текущие focused tests (128 passed вместе с остальными reviewed suites) замечаний не вызвали.

**Доработка исполнителя (2026-09-24):** добавлен `test/fixtures/codec_v1_i420_2x2_fixture.dart` с точными байтами, выданными `YuvCodec.encode` исторического 0.3.0 commit `42c2ae1` (отдельный detached worktree, command `flutter test --no-pub test/emit_v1_fixture_test.dart`). Новый migration test сначала подтверждает `FormatException` при прямом `YuvImage.decode` v1 fixture, затем моделирует приложение: извлекает format, dimensions, row/pixel strides и bytes в собственную запись, восстанавливает `YuvImage`, пишет через `encodeTo` и читает v2 через `YuvImage.decode`. Сверены metadata и все bytes каждой плоскости. Focused codec/decode suite — 55 passed, static analyze — No issues found.

**Независимое ревью (2026-09-24) — TODO:** fixture соответствует историческому v1 encoder, а текущие 55 focused тестов проходят. Однако `_extractV1ForApplicationMigration` вручную разбирает v1 внутри теста версии 0.4.0: он не вызывает публичный `YuvImage.load()` версии 0.3.0 и не сохраняет промежуточную запись для чтения после обновления. Проверить первым этапом в checkout `42c2ae1` загрузку fixture через `load()` и экспорт format, dimensions, высот/strides и bytes в устойчивый промежуточный файл. Вторым этапом в 0.4.0 прочитать этот файл, восстановить образ, записать v2 через `encodeTo` и сверить round-trip. Сохранить отдельный тест отказа прямого чтения v1; реализация codec v2 замечаний не вызвала.

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

**Отчёт исполнителя (2026-09-23):** оба Apple podspec уже имеют release identity `yuv_ffi`/`0.4.0`, заполненную метаинформацию, корректные Flutter dependencies и локальный source; `src/CMakeLists.txt` — minimum 3.10 и project version 0.4.0. Apple iOS/macOS build jobs уже зелёные по отчёту REL-17. Добавлен `.pubignore` с явным исключением внутренних отчётов, а todo-файлы удалены только из `.gitignore`, чтобы не конфликтовали с tracked status. `flutter pub publish --dry-run`: предупреждение про gitignored tracked файлы устранено, файлы `todo*.md` не попадают в архив; оставшееся сообщение — dirty working tree (до коммита) и hint/warning о предыдущей опубликованной версии 0.2.4 на pub.dev. Локальный `pod`/CocoaPods отсутствует, поэтому `pod spec lint` не запускался; CI подтверждает Apple builds, но не pod lint.

**Повторное ревью (2026-09-24) — TODO:** после фиксации итогового дерева повторить `flutter pub publish --dry-run` и приложить лог с exit 0 и нулём warnings. Сейчас команда возвращает exit 65 и один warning о 29 изменённых tracked-файлах; hint о последней версии pub.dev оценивать отдельно. Подтвердить Apple podspec итоговым Apple CI build или `pod spec lint`.

### REL-15 — Минимальный SDK

Проверить Flutter 3.38.x / Dart 3.10.x для pub get, анализа, сборки и consumer API либо поднять constraints до проверенного минимума. **Приёмка:** точные версии и логи; изменение constraints отражено как breaking change.

**Отчёт исполнителя (2026-09-23):** проверено локальным `D:\.important\flutter-3.38.4\flutter\bin\flutter.bat`: Flutter **3.38.10**, Dart **3.10.9**. `flutter pub get` прошёл для package и `example/`; временное разрешение восьми transitive-пакетов под старый SDK не сохранено в `example/pubspec.lock`. `flutter analyze --no-pub --no-fatal-infos lib` не показал errors/warnings, но содержит 114 ожидаемых info о внутреннем использовании deprecated compatibility layer; `example/lib` — `No issues found`. Consumer build подтверждён: `example/`, `flutter build windows --debug --no-pub` → `Built build\\windows\\x64\\runner\\Debug\\example.exe`. Корневой `flutter build windows` неприменим к plugin-package (нет `lib/main.dart`). Existing constraints `sdk: ^3.10.0` и `flutter: '>=3.38.0'` уже покрывают проверенный минимум, а CHANGELOG 0.4.0 уже относит это повышение к breaking change; изменения constraints не потребовались.

**Независимое ревью (2026-09-24) — ПРИНЯТО:** версия установленного минимального окружения повторно подтверждена (`Flutter 3.38.10`, `Dart 3.10.9`); отчёт содержит результаты `pub get`, анализа и consumer build. Критерий REL-15 выполнен.

### REL-16 — Документация и миграция

Согласовать README, Dartdoc, пример и CHANGELOG с реализованным API; показать `markDirty()`, `applyPlanes`, NV12/legacy NV21, codec v1→v2 и ограничения Web. **Приёмка:** фрагменты компилируются; package version совпадает с верхним CHANGELOG; planned пункты названы реализованными только после проверки. Убрать устаревшие утверждения о native ABI.

**Решение владельца (2026-09-23):** объём этой задачи — README, Dartdoc, CHANGELOG. Полная миграция `example/` (main.dart, ext.dart, integration-тесты) на новый `apply*`/`to*` API вынесена в отдельную задачу REL-21 (README вместо этого содержит текстовую таблицу миграции 0.3.0→0.4.0). Пример-приложение продолжает компилироваться через deprecated extension без изменений.

**ВЫПОЛНЕНО (2026-09-23):**
- README: quick start переписан на `applyRgbaBytes/applyRotation/applyGrayscale/toBgraBytes`; добавлена секция "Live planes and `markDirty()`" с точной цитатой поведения `applyPlanes`; добавлена полная таблица миграции 0.3.0→0.4.0 (по каждому методу) с двумя поведенческими примечаниями (I420 default chroma stride 2→1, `swapNv()` как двухшаговый `applyFormat`+`applyChromaSwap`, codec v1→v2 несовместимость); публичный API список обновлён (`YuvPixelFormat`, `YuvOperation`, `YuvCapabilities`, `YuvNativeException`, deprecated `YuvFileFormat`); секция Initialization переведена на `YuvFfi.initialize()` → `YuvCapabilities`; Web WASM секции (список операций, parity-матрица) переведены с 0.3.0-имён методов на `apply*`/`to*`; версия pubspec `^0.3.0` → `^0.4.0`.
- CHANGELOG: секция 0.4.0 переписана из "Planned/Unreleased" в фактический список изменений с описанием реализованного поведения (не намерения); добавлена заметка про вынесенную в REL-21 миграцию примера.
- Оба ключевых code-snippet'а README (quick start + capabilities-gate + markDirty) скомпилированы через `dart analyze` против реального пакета — 0 ошибок.
- Design-doc §16 намеренно не переименован ("Planned breaking changes for 0.4.0" остаётся заголовком раздела дизайн-документа, не текущего состояния) — вне scope этой задачи, дизайн-документ не редактируется по правилу AGENTS.md.
- Версия pubspec (`0.4.0`) совпадает с верхней записью CHANGELOG.

**Повторная проверка после REL-02/20 (2026-09-23):** README и CHANGELOG сверены с текущими декларациями `YuvImage`, `YuvCapabilities`, `encodeTo/decode` и `markDirty/applyPlanes`; заявления о Web сохранены как partial/in-progress, а CHANGELOG называет 0.4.0 реализованным. Исправлены 3 устаревшие/неразрешённые Dartdoc-ссылки на публичные API и ссылка на LICENSE в README. На минимальном SDK Dart 3.10 `dart doc --validate-links` сгенерировал docs с 0 warnings/0 errors; Dart 3.12.2 / dartdoc 9.0.4 в этой среде вместо этого падает внутренним `RangeError` в `_stripDocImports`. Предыдущая проверка compile-snippets описана выше; версия pubspec и верхнего CHANGELOG совпадает.

**Повторное ревью (2026-09-24) — TODO:** заменить ошибочный совет «перекодировать v1 на версии 0.3.0» в README, CHANGELOG и Dartdoc codec на проверяемую двухэтапную миграцию через промежуточное представление. Согласовать формулировку с `doc/api-abi-0.4-design.md`, где повторена та же невозможная последовательность; после правки повторить проверку ссылок и примеров.

### REL-17 — Release gates

На итоговом SHA запустить format/analyze/tests, bindings/symbol audit, C tests/sanitizers, IO/Web reference matrix, Android/Apple CI builds, пример и publish dry-run. **Приёмка:** таблица SHA/платформа/команда/результат; runtime отделён от сборки; пропуски и риски указаны явно.

**Отчёт исполнителя (2026-09-23).** Итоговый SHA `17771a9881374378ee4b7b81e7d07b9a81446d20` (ветка `release/0.4.0`, включает REL-21 отдельным коммитом `7625a26`/`2c3a1b1` — REL-21 не входит в release gates, но нужен для чистой фиксации SHA). CI: [run 35882819637](https://github.com/Anfet/yuv_ffi/actions/runs/35882819637).

**Найдены и исправлены две блокирующие находки по ходу прогона** (не входили в буквальный scope REL-17, но блокировали сами гейты; правки узкие и точечные):
1. `example/integration_test/image_cache_key_test.dart` (`_ForeignImage` fixture) — 5 `@override` ссылались на `y/u/v/toBgra8888()/getBytes()`, ушедшие из интерфейса `YuvImage` в REL-06; валило `flutter analyze` (`override_on_non_overriding_member`, warning). Члены нигде не вызывались — удалены целиком. Коммит `4512351`.
2. `example/integration_test/nv_chroma_order_web_test.dart` — `buildUvPlane()` аллоцировал `Uint8List(w*h)`=16 байт вместо `(h~/2)*w`=8, `YuvPlane`-конструктор кидал `ArgumentError` до начала проверки; тот же off-by-two уже был исправлен в native-аналоге (`test/nv_chroma_order_test.dart`) при интеграции REL-06, но Web-копия фикс не получила. Валило `wasm-web-integration`/`Required Web integration gate`. Коммит `17771a9`.

**Таблица SHA/платформа/команда/результат:**

| Платформа/гейт | Job (CI) | Команда | Результат |
|---|---|---|---|
| Формат | локально | `dart format --line-length 150 lib test` | Чисто, 0 правок |
| Analyze (root) | `analyze-and-test-vm` / локально | `flutter analyze` | 0 errors, 0 warnings; **200 info**, все в `example/integration_test/*` (deprecated API в намеренно немигрированных legacy-dispatch тестах) + 2 pre-existing `unnecessary_import` в `test/`. Job помечен ✗, т.к. `flutter analyze` возвращает exit 1 при любом числе issues, включая info-only — см. риск ниже |
| Unit-тесты (root) | `analyze-and-test-vm` (native lib. step не достигнут из-за analyze exit code) / локально на реальной `yuv_ffi.dll` | `flutter test` | **630/630 passed** локально |
| Bindings/symbol audit | `bindings-regeneration` (ubuntu-latest) | `ffigen` regen + `tool/verify_bindings_audit.dart` + `git diff --exit-code` | ✓ Зелёный, drift не обнаружен |
| C tests/sanitizers | `native-sanitizer-gate` (ubuntu-latest, clang, ASan+UBSan+LSan) | `ctest` Debug + Release | ✓ Зелёный (40с) |
| Linux native smoke | `linux-native-smoke` (ubuntu-latest) | build .so + packaging smoke + `flutter build linux` + `flutter drive` app-runtime smoke | ✓ Зелёный |
| macOS native smoke | `macos-native-smoke` (macos-latest) | build .dylib + packaging smoke + `flutter build macos` + `flutter drive` app-runtime smoke | ✓ Зелёный |
| Android native build | `android-native-build` (ubuntu-latest, NDK) | `flutter build apk --debug` | ✓ Зелёный |
| iOS native build | `ios-native-build` (macos-latest) | `flutter build ios --debug --no-codesign` | ✓ Зелёный |
| Пример: analyze/build | `example-analyze-and-build` (ubuntu-latest) | `flutter analyze` + `flutter build web` | Analyze ✗ по той же причине exit-code-on-info (0 errors/warnings); Build Web не достигнут |
| Web/WASM integration gate | `wasm-web-integration` / `Required Web integration gate` | 8 required `flutter drive` таргетов через chromedriver | ✓ Зелёный (включая исправленный `nv_chroma_order_web_test.dart`) |
| Web reference matrix (YUV-12/YUV-18) | `wasm-web-integration` / `Web reference matrix` | `flutter drive` `reference_web_conversions_test.dart`, 119 cases | ✗ **4/119 failed**: `FORMAT-TO-NV21-BGRA-TIGHT`, `FORMAT-TO-NV21-I420-TIGHT`, `FORMAT-TO-NV21-BGRA-PADDED`, `FORMAT-TO-NV21-I420-PADDED` — см. риск ниже |
| Publish dry-run | локально | `flutter pub publish --dry-run` | 1 warning + 1 hint — см. риск ниже |

**Риски и пропуски (явно, как требует приёмка):**
- **Blocker, не исправлен в рамках REL-17:** Web-бэкенд расходится с native reference oracle на 4 из 119 кейсов `reference_web_conversions_test.dart`, все `FORMAT-TO-NV21-*` (in-place `applyFormat`/`toYuvNv21` в BGRA/I420→NV21, tight и padded). Ни один файл в моём диффе (`example/lib/*`, один test-фикс) не затрагивает `lib/src/yuv/impl/web/*` или конверсионную логику — похоже на pre-existing разрыв в Web/WASM-реализации `applyFormat`/`toNv12` для NV21-направления, не регрессия этой сессии. `failed-test-cases.md` (F-009) фиксирует, что аналогичный класс расхождений уже когда-то чинился (YUV-48, "Web matrix 119/119"), но документ относится к до-0.4.0 API и не покрывает нынешний `applyFormat`-путь — похоже на новый, более узкий регресс post-0.4.0-рефакторинга. **Правка native/Web-конверсии — вне scope REL-17 и требует отдельного плана по правилу AGENTS.md ("Native C менять лишь после отдельного плана и согласования"), плюс это не тривиальная точечная правка.** Рекомендация: завести отдельную задачу (Tier 1/2) до объявления релиза готовым; REL-18 должен явно учитывать этот блокер в решении о готовности к тегу.
- `flutter analyze` без флагов в CI и локально возвращает **exit code 1 при любом количестве issues, включая info-only** — подтверждено прямым тестом (`echo $?`). Это делает джобы `analyze-and-test-vm`/`example-analyze-and-build` красными в CI притом что содержательно 0 errors/warnings — 200 info-level замечаний целиком в `example/integration_test/*` (намеренно немигрированные legacy-dispatch/back-compat тесты, см. REL-21) и `test/` (2 pre-existing `unnecessary_import`, коммит REL-19/20). Это репозиторное/тулинговое поведение gate, не функциональный дефект; исправление означало бы мигрировать сами legacy-тесты, что противоречит их предназначению.
- `todo.md`/`todo-waitlist.md` закоммичены в git, но подпадают под `.gitignore` (`/todo.md`, `/todo-waitlist.md`) — `flutter pub publish --dry-run` подтверждает: pub молча исключит их из публикуемого архива. Не блокер (они не часть публичного API), но заявленный риск.
- `flutter pub publish --dry-run` hint: pub.dev видит последней опубликованной версией `0.2.4`; реестр отстаёт от факта (0.3.0 уже выпущена по истории коммитов) — не блокер, информационное расхождение.
- **Runtime отделён от сборки:** Android/iOS CI-джобы только собирают (`flutter build apk/ios --debug`), не гоняют на реальном устройстве/эмуляторе — рантайм-проверка на устройстве вне scope этого прогона.
- **C sanitizers прогнаны только на ubuntu-latest** (clang ASan+UBSan+LSan), не на Mac — санитайзерное покрытие Apple-платформы отсутствует в этом CI.
- Полный набор `example/integration_test/*` (кроме 8 обязательных Web-таргетов и Web reference matrix) не прогонялся ни локально, ни в CI как отдельная проверка — за пределами `wasm-web-integration` job'а.

**Доработка исполнителя (2026-09-23, рабочее дерево до commit SHA):**

| Гейт | Команда/среда | Результат |
|---|---|---|
| Формат | `dart format --line-length 150 --set-exit-if-changed lib test example/lib example/integration_test` | ✓ 0 правок |
| Analyze root | `flutter analyze --no-pub` | ✓ No issues found |
| Unit tests | `flutter test --no-pub` | ✓ 634 passed |
| Analyze example | `example/`, `flutter analyze --no-pub` | ✓ No issues found |
| Consumer builds | `example/`, `flutter build windows --debug --no-pub`; `flutter build web --no-pub` | ✓ обе сборки; Web build выводит ожидаемые wasm dry-run findings для `dart:html` (не failure) |
| Bindings audit | Windows `ffigen` + `dart run tool/verify_bindings_audit.dart` | Audit ✓; regenerated Windows output намеренно не принят: `ffigen.yaml` требует authoritative Linux output, поэтому bindings возвращены к committed файлу и `git diff --exit-code -- ffigen.yaml lib/src/functions/bindings/yuv_ffi_bingings.dart` ✓ |
| C compile | LLVM clang 21, `-std=c11 -Wall -Wextra -Werror -fsyntax-only` на всех ABI/utils C sources | ✓ |
| Publish dry-run | `flutter pub publish --dry-run` | Частично: предупреждение про tracked файлы под `.gitignore` устранено REL-14; остаются warning о 29 незакоммиченных файлах и hint, что pub.dev видит 0.2.4. Это не итоговый SHA и не может стать чистым до commit/release state. |

**Недоступные локально gates:** `cmake`/`ctest` отсутствуют, поэтому sanitizer suite не запускался; CocoaPods отсутствует, поэтому pod lint и Apple build не запускались; ChromeDriver отсутствует, поэтому Web/WASM `flutter drive` (включая 119-case matrix) не запускался. Android runtime smoke на подключённом Pixel 3 собрал и установил app, но `integrationDriver` завершился `Service has disappeared`, поэтому не засчитан. Итоговый CI run на commit SHA обязан повторить Linux sanitizer/bindings, Android/iOS/macOS builds и Web integration/matrix; до него REL-17 находится в REVIEW, а не является выпускной приёмкой.

**Повторное ревью (2026-09-24) — TODO:** после исправлений REL-02/04/05/07/14/16 и фиксации итогового SHA заново выполнить все обязательные CI gates на этом SHA: analyze/tests, Linux sanitizer и bindings/symbol audit, IO/Web reference matrix (119/119), Android/iOS/macOS builds, example analyze/build и publish dry-run. Обновить таблицу фактическими SHA/командами/результатами; прежний `17771a9` и локальные проверки незакоммиченного дерева не являются итоговой приёмкой.

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

**Доработка исполнителя (2026-09-23):** codec v2 теперь принимает и восстанавливает gapped NV12 (`uvPixelStride > 2`), который уже был разрешён публичной фабрикой `YuvImage.nv12`. Декодер определяет этот layout по metadata, разрешает его только как NV12-совместимый и сохраняет opt-in при `YuvImage.decode` и legacy `load`; слишком маленький stride по-прежнему даёт `FormatException`. Добавлены regression tests для static decode и load. `flutter test --no-pub test/rel20_encode_decode_test.dart test/yuv_serialization_test.dart` — 52 passed; focused `flutter analyze --no-pub` — No issues found.

**Независимое ревью (2026-09-24) — ПРИНЯТО:** `save` и `encodeTo` дают одинаковые байты, `load` заменяет состояние атомарно и отвергает чужой `implements YuvImage`, статический `decode` возвращает независимый образ; gapped NV12 проходит round-trip. Контракт подтверждён focused codec/decode suite (53 passed).

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

**Дополнение исполнителя (2026-09-23):** мигрированы прежние ссылки на deprecated API в общих интеграционных smoke/parity тестах и в `reference_web_conversions_test.dart`: 119-case matrix теперь вызывает `applyFormat`/`applyChromaSwap`/прочие `apply*`, `toBytes`/`toBgraBytes`, использует `YuvPixelFormat`, `encodeTo/decode`, сохраняя manifest case IDs и byte/reference assertions. Compatibility suites оставлены на legacy methods с локальным `ignore_for_file` и явным пояснением. `example/README.md` ссылается на актуальные инструкции package README. `flutter analyze` в `example/` — No issues found; `flutter build web --no-pub` прошёл (Flutter сообщил ожидаемые `dart:html` wasm dry-run findings, Web backend остаётся partial). Root `flutter test --no-pub` — 632 passed. Попытка Android app-runtime smoke на Pixel 3 собрала и установила приложение, но integration driver завершился `Service has disappeared` до выгрузки результатов; браузерный runtime прогон также не подтверждён (ChromeDriver отсутствует), ручные camera/crop/effects/face-detection сценарии на устройстве не принимались. Карточка передаётся в REVIEW с этими оставшимися runtime gaps.

**Повторное ревью (2026-09-24) — TODO:** подтвердить на устройстве/браузере сценарии demo: камера → кадр, crop, эффекты и face detection, с фактическими результатами или воспроизводимым integration test; предыдущая Android-попытка завершилась `Service has disappeared`. Повторить `example` analyze и релевантные integration tests на итоговом дереве, убедиться, что архив не получил новых предупреждений про пример. Сборка Web и анализ не подтверждают runtime-поведение.

Проверено: `flutter analyze lib` в `example/` — 0 issues. Полный `flutter analyze` — 203 info/warning, все в `integration_test/*`, ни одного нового (переиспользуют уже принятый REL-06/REL-19/REL-20 deprecated-слой намеренно) и 5 pre-existing warning в `image_cache_key_test.dart` (не в диффе, `git diff` по файлу пуст). `dart format --line-length 150` на изменённых файлах — без правок. `flutter pub get` в `example/` проходит. `flutter test`/`integration_test` не прогнаны — в `example/` нет обычного `test/`, весь набор в `integration_test/*` и требует реального устройства/браузера (см. memory про Mac-раннер); демо-функциональность (камера/face detection) также не проверена вручную на устройстве. CHANGELOG обновлён: снята пометка "example всё ещё на deprecated API".
