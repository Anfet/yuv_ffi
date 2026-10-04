# FIX 9 — MIGRATION.md: переход с 0.2.4 на 0.5.0 для инженеров и агентов
**Status:** REVIEW · **Tier:** T2, Reviewer T1 · **Owner:** — · **Depends On:** FIX 6 · **Probe:** none

**Base SHA:** `8bab4a74e6fa0f41097832e8381100999210efc4`

#### Goal

Пользователь 0.2.4 переходит на 0.5.0 через изменения двух записей CHANGELOG (0.4.0 retracted и 0.5.0) и таблицу
README «Migrating to 0.5.0». Таблица короткая: в ней не разделены механические переименования и замены, которые
меняют семантику (мутация вместо новой копии, layout плоскостей, порядок UV, формат сериализации). Нет порядка шагов,
шаблонов поиска старых вызовов и проверки, что миграция завершена. Нужен один отдельный документ, по которому
инженер переносит код осознанно, а ИИ-агент механически заменяет безопасные вызовы и не трогает остальные без
решения.

#### Architect Decision

1. **Новый `MIGRATION.md` в корне пакета**, на английском (правило 9). Единственный подробный источник перехода
   0.2.4 → 0.5.0; lockfile с 0.4.0 — та же миграция (D-28). Структура:
   - **Scope.** Откуда и куда, ограничение `yuv_ffi: ^0.5.0`, минимумы Dart/Flutter/Android/iOS/macOS, исключённый
     Android `x86`.
   - **Steps.** Упорядоченный чек-лист: зависимость → инициализация → механические замены → семантические замены →
     сохранённые данные → проверка.
   - **Mechanical replacements.** Таблица: `0.2.4 call` | `0.5.0 call` | `rg` pattern для поиска | Kind. Kind —
     `rename` (поведение и байты те же, заменять механически) или `review` (поведение отличается, см. раздел ниже).
     Одна строка — один символ или одна форма вызова; формы с разными аргументами (`rect:` → `region:`) — явно.
   - **Changes that need a decision.** Для каждой строки `review` — до/после, чем отличается поведение и правило
     выбора. Минимум: `toYuvI420()`/`toYuvNv21()`/`toYuvBgra8888()` (мутировали → `applyFormat` или `toI420()`/...),
     `load(stream)` → `YuvImage.decode`, `copy(blank: true)` → `YuvImage.allocate`, `nv21` → `nv12` (фактический
     порядок UV в 0.2.4 — по исходнику, без допущений), `swapNv()` на не-NV12, `planes:` и `YuvPlaneLayout`,
     `uvPixelStride` по умолчанию, `YuvFfi.initialize()` в каждом isolate, `markDirty()`, типы исключений,
     `implements YuvImage`.
   - **Behavior changes without compile errors.** Список из README, каждый пункт с тем, как его обнаружить в коде.
   - **Stored frames.** Процедура переноса кадров v1 через собственное представление приложения (CHANGELOG 0.4.0);
     явно: автоматической миграции нет, v1 re-save не использовать.
   - **Native and Web consumers.** Прямые вызовы удалённых символов `yuv420_*`/`nv21_*`/`bgra8888_*` → ABI v1; Web —
     JavaScript-сборка, `--wasm` не поддерживается.
   - **Verify.** Команды `rg`, которые после миграции должны быть пусты, затем `flutter analyze` и тесты приложения.
   - **For automated agents.** Короткие правила: менять только строки `rename`; для `review` выбирать по правилу из
     раздела или оставлять TODO-комментарий для инженера; не трогать сохранённые данные и native-код; закончить
     разделом Verify.
2. **Источники и сверка.** Старое API — только `git show 0.2.4:<path>`, новое — текущий публичный API (`lib/yuv_ffi.dart`
   и экспорты). Ни одна строка не пишется по памяти или по CHANGELOG без сверки с кодом. Утверждения о поведении
   — только те, что уже записаны в CHANGELOG/README или подтверждены кодом; новых обещаний нет.
3. **README.** Раздел «Migrating to 0.5.0» сокращается до вводной, 4–6 главных пунктов и ссылки на `MIGRATION.md`;
   полная таблица живёт только в `MIGRATION.md`, чтобы не было двух расходящихся копий. Абзац о Web (строки 36–37):
   убрать неверную причину «relies on browser JavaScript APIs» — Web-слой построен на `dart:js_interop` и
   `package:web`. Формулировка: `--wasm` собирается, но операции падают во время выполнения (известная ошибка interop,
   `doc/web-parity.md`); использовать `flutter build web`.
4. **CHANGELOG 0.5.0.** В Breaking changes и «Updating from 0.2.4 or a 0.4.0 lockfile» ссылку на таблицу README
   заменить ссылкой на `MIGRATION.md`; в Known limitations — та же поправка причины `--wasm`, что в README.

#### Scope

`MIGRATION.md` (новый), `README.md`, `CHANGELOG.md` (только запись 0.5.0, пункт 4).

#### Constraints

- Код, API, `pubspec.yaml` и версия не меняются. Язык — английский.
- Ссылка из README на `MIGRATION.md` работает на pub.dev и GitHub (относительная ссылка; `repository` в `pubspec.yaml`
  задан).
- Safari и Firefox — «not verified» (D-27); о сроках исправления `--wasm` не обещать.

#### Definition of Done

- `MIGRATION.md` содержит все разделы пункта 1; каждый удалённый в 0.4.0/0.5.0 публичный символ 0.2.4 есть в таблице
  ровно одной строкой с Kind.
- README ссылается на `MIGRATION.md` и не дублирует таблицу; причина ограничения `--wasm` в README и CHANGELOG верна.
- Механическая миграция по документу проверена на фикстуре (Validation).

#### Validation

- Полнота: список публичных членов 0.2.4 (`git show 0.2.4:lib/...`) сравнить с текущим API; каждый отсутствующий в
  0.5.0 символ найден в таблице.
- Фикстура: в scratchpad пакет с `yuv_ffi: 0.2.4` (из `git archive 0.2.4`, path-зависимость), один файл вызывает
  каждую строку таблицы; `flutter analyze` чистый. Затем копия файла переводится на `path: D:/.projects/yuv_ffi`
  только по `MIGRATION.md`; `flutter analyze` — без ошибок, все `rg` из Verify пусты. Фикстура не коммитится.
- Сниппеты `MIGRATION.md` и README компилируются тем же способом, что в FIX 6.
- `flutter pub publish --dry-run` — 0 warnings; `MIGRATION.md` в архиве.
- Reviewer: передать `MIGRATION.md` и исходный файл фикстуры отдельному агенту без другого контекста и сравнить его
  результат с ручной миграцией; расхождение в строке `rename` — дефект документа.

#### Executor Report

- Добавлен `MIGRATION.md`: область и минимумы, пошаговая миграция, таблица публичных удалений 0.2.4 с `rg`-шаблонами и `rename`/`review`, разбор семантики NV21/UV, мутаций, сериализации, плоскостей, ошибок, native/Web и инструкции автоматическим агентам. Удалённые объявления сверены с `git show 0.2.4:lib/...`, замены — с текущими экспортами и `YuvImage`.
- README сокращён до краткого маршрута перехода и ссылки на `MIGRATION.md`; в README и верхней записи CHANGELOG исправлена причина отказа `--wasm`: сборка проходит, WASM-вызовы операций падают во время выполнения из-за interop return-value mismatch. Safari/Firefox отмечены как непроверенные.
- PASS: вызовы таблицы миграции собраны во временном Flutter-пакете с `yuv_ffi: path: D:/.projects/yuv_ffi`; `flutter analyze` — No issues found (scratchpad `C:\Users\Oleg-T\AppData\Local\Temp\fix9-snippets-e8d0698f3ed94ddfa4324dbd367a0e60`).
- PASS: исходная API-фикстура собрана против `git archive 0.2.4` и path-зависимости; `flutter analyze` — No issues found (scratchpad `C:\Users\Oleg-T\AppData\Local\Temp\fix9-api-fixture-0eb5f9ef21b84887ac9a021909818854`). Её вызовы перенесены в текущую API-фикстуру по таблице; текущая фикстура тоже анализируется без ошибок.
- PASS: `git diff --check`.
- Пробы не требуются (`Probe: none`). `scope_guard.sh` в общем рабочем дереве вернул `all` из-за уже существующих изменений файлов вне scope FIX 9; эти команды не запускались.
- `flutter pub publish --dry-run` не запускался: по правилу проекта он валидируется на чистом закоммиченном SHA, а в рабочем дереве есть посторонние незакоммиченные изменения.

#### Review

- **Вердикт: REWORK → TODO (04.10.2026).** Проверены незакоммиченные изменения FIX 9 относительно базы `8bab4a74e6fa0f41097832e8381100999210efc4`; принятого SHA нет. Проверка других изменений рабочего дерева не входит в это ревью.
- **P2 — MIGRATION.md:65, рецепт сохранения blank-layout теряет padding.** Named factory с zeroed `YuvPlane` по умолчанию упаковывает плоскости. Независимый scratch-тест: rowStride `[8, 4, 4]` превратился в `[4, 2, 2]`; только `layout: YuvPlaneLayout.preserve` сохранил `[8, 4, 4]`. Указать этот аргумент прямо в рецепте. Уточнить и описание старого `copy(blank: true)`: исходник 0.2.4 сохранял pixelStride, но заново вычислял rowStride, а не сохранял произвольный padding источника.
- **P2 — MIGRATION.md:39–41,68–69, не описана миграция blur-вызовов с defaults.** В 0.2.4 `gaussianBlur()`, `boxBlur()` и `meanBlur()` допустимы; radius по умолчанию — 2, 10, 2 соответственно, sigma Gaussian — 2. В новом API radius обязателен у всех трёх методов, sigma тоже обязателен у Gaussian. Документ говорит только о sigma и `rect:` → `region:`. Добавить формы без radius/sigma и явные правила переноса прежних defaults. Независимый analyze воспроизвёл три `missing_required_argument` для radius; текущая фикстура исполнителя покрывает только явные radius/sigma и пропускает эти формы.
- **P3 — MIGRATION.md:70, неверная семантика старого swapNv().** В обоих backend 0.2.4 метод сначала выполнял `toYuvNv21()` для другого формата, затем swap. Ограничение NV12 и `UnsupportedError` относится к новой `applyChromaSwap()`. Описать эту разницу явно и показать последовательность `applyFormat(YuvPixelFormat.nv12)` → `applyChromaSwap()` для сохранения прежнего поведения.
- **P3 — CHANGELOG.md:11, оставшаяся ссылка на README mapping.** Таблица оттуда удалена; Architect Decision п. 4 требует ссылку на MIGRATION.md также в Breaking changes. Исправить эту ссылку.
- **Независимая проверка:** `flutter analyze --no-pub` старой API-фикстуры — PASS; текущей фикстуры snippets — PASS. Все три команды Verify из документа на старой фикстуре находят legacy-код, на текущей возвращают exit 1 (совпадений нет); экранирование корректно. `git diff --check` — PASS. Старый публичный API, exports и спорная семантика сверены с `git show 0.2.4:<path>` и текущим кодом.
- Scratch воспроизведения: `C:\Users\Oleg-T\AppData\Local\Temp\fix9-review-73e5cfcec9ec4fce8607c14d84ba7680`; `analyze.log` — ожидаемый FAIL негативного случая defaults (3 ошибки), `layout-test.log` — PASS, 1 тест, с фактическими strides. Пробы не нужны (`Probe: none`). Процессы проверок завершены.
- **Оставшаяся Validation:** dry-run и включение MIGRATION.md в архив не подтверждены; выполнить на чистом закоммиченном SHA. Изолированная миграция отдельным агентом не выполнялась: прямое указание Engineer устанавливает бюджет подагентов 0 и имеет приоритет над Validation карточки. Перед повторным ревью расширить фикстуру формами вызовов с defaults и blank-image с padding.

#### Rework plan — обязательный объём перед повторным REVIEW

Доработка документов, без изменений production-кода и API. Закрыть все четыре замечания Review одним проходом. Ниже — конкретизация доработки, а не замена исходных DoD и Validation. Делегирование не требуется и запрещено текущим указанием Engineer.

1. **Blank-image и layout (P2).** В Changes that need a decision разделить два факта:
   - старый `copy(blank: true)` сохранял размеры/формат и pixelStride, но rowStride вычислял заново; произвольный padding исходника не сохранялся;
   - если приложение сознательно хочет сохранить полный layout, создать zeroed planes с исходными `height`, `rowStride`, `pixelStride` и передать **`layout: YuvPlaneLayout.preserve`** в соответствующую named factory. Добавить компилируемый пример для I420; не оставлять выбор layout неявным. `allocate` оставить вариантом tightly packed blank-image. Не обещать ему эквивалентность старому blank-copy при pixelStride > 1.
2. **Blur defaults (P2).** В существующих строках таблицы явно перечислить формы без аргументов и с частично заданными аргументами; не дублировать удалённый символ отдельными несогласованными строками. В семантическом разделе дать точные замены:
   - `gaussianBlur()` → `applyGaussianBlur(radius: 2, sigma: 2.0)`;
   - `gaussianBlur(radius: r)` → `applyGaussianBlur(radius: r, sigma: 2.0)`;
   - `gaussianBlur(sigma: s)` → `applyGaussianBlur(radius: 2, sigma: s.toDouble())`, когда `s` — int; оба явно переданных аргумента сохраняются, int sigma преобразуется в double;
   - `boxBlur()` → `applyBoxBlur(radius: 10)`; `boxBlur(rect: rect)` → `applyBoxBlur(radius: 10, region: rect)`;
   - `meanBlur()` → `applyMeanBlur(radius: 2)`; `meanBlur(rect: rect)` → `applyMeanBlur(radius: 2, region: rect)`;
   - для Box/Mean явно заданный radius сохранить, `rect:` заменить на `region:`. При явных числовых литералах Gaussian sigma использовать double-литерал. Все строки остаются `review`; не обещать идентичность старого и нового blur по байтам только на основании переноса аргументов.
3. **swapNv (P3).** Указать: в 0.2.4 другой формат сначала автоматически конвертировался в NV21-labeled UV, затем выполнялся swap; новое API принимает только NV12. Для NV12 — `applyChromaSwap()`, для сохранения маршрута из другого формата — `applyFormat(YuvPixelFormat.nv12)` и затем `applyChromaSwap()`. Добавить пример с I420. Не описывать старый метод как NV12-only.
4. **CHANGELOG (P3).** В Breaking changes верхней записи заменить `README mapping` прямой Markdown-ссылкой `[MIGRATION.md](MIGRATION.md)`. Проверить обе ссылки верхней записи и ссылку README; таблица должна остаться только в MIGRATION.md.

#### Rework validation и критерий возврата

- **Сверка исходников:** заново сверить изменённые утверждения со старым кодом через `git show 0.2.4:...` и текущими публичными экспортами. В отчёте дать конкретные пути для defaults, blank-copy и swapNv. Не брать ожидаемые значения только из текста этого плана.
- **Расширенная API-фикстура:** исходная версия должна анализироваться против 0.2.4; мигрированная — против текущего пакета. Включить все формы blur из п. 2, integer-переменную sigma, NV21/NV12 swap и I420 swap, оба значения `blank`, копию с pixelStride > 1, supplied planes с padding и `layout: preserve`. Сохранить покрытие остальных строк исходной таблицы. Каждый пример пометить соответствующей строкой/правилом MIGRATION.md; переносить только по окончательному документу. Анализ обеих версий — без issues; примеры нового документа включить в анализируемый файл. Исполнительский scratch не коммитить.
- **Layout runtime:** в отдельном scratch-тесте использовать I420 4×4 с zeroed planes `(height,rowStride,pixelStride) = (4,8,1), (2,4,1), (2,4,1)`. По рецепту сохранения layout итоговые rowStride должны быть `[8,4,4]`, pixelStride `[1,1,1]`, все bytes — 0; при фабрике без `preserve` контроль даёт `[4,2,2]`. Отдельно сравнить старый blank-copy и новый явно выбранный способ при pixelStride > 1; фиксировать реальные strides и длины buffers. Это проверка рецепта, а не проверка compile-time.
- **Verify с негативным контролем:** выполнить точные команды из окончательного документа на старой и мигрированной фикстурах. На старой должны находиться известные legacy-вызовы (exit 0), на новой совпадений нет (exit 1); exit 2 — ошибка, не PASS. Перечислить покрытые команды и итог в отчёте. Проверить `git diff --check`.
- **Publish dry-run:** нужен exit 0, 0 warnings и подтверждение включения MIGRATION.md в публикуемый список файлов. Выполнить на чистом закоммиченном SHA, содержащем итог FIX 9. Посторонние изменения основной копии не откатывать и не включать в коммит задачи; при необходимости использовать временный export этого SHA через `git archive` (не worktree). Результат dirty-tree failure не засчитывать. Если нужный чистый SHA ещё не доступен, записать конкретный блокер и оставить задачу без REVIEW; повторно сдавать с пометкой «dry-run не запускался» нельзя.
- **Отчёт:** указать проверенный SHA, пути scratch и логов, команды/exit codes, результаты каждого из четырёх исправлений и всех проверок выше. Статус карточки и дашборда менять вместе. Пробы backend не требуются (`Probe: none`); общий `all` от посторонних изменений не превращать в требование запускать всю матрицу для этой документационной доработки.
- **Граница повторного ревью:** ни одного открытого P2/P3 из Review; старая и новая расширенные фикстуры, layout runtime, Verify и dry-run подтверждены. Изолированная агентная миграция из первоначальной Validation исключена прямым бюджетом Engineer 0; заменить её самостоятельным переносом расширенной фикстуры по документу и указать это ограничение в отчёте, не заявлять проверку вторым агентом.

#### Executor Report — Rework

- Исправлены четыре замечания ревью. `copy(blank: true)` уточнён по обоим старым backend: новый blank пересоздавал плоскости, сохраняя pixelStride и вычисляя rowStride заново; добавлен компилируемый I420 пример с исходными высотами/страйдами и обязательным `layout: YuvPlaneLayout.preserve`. Для blur указаны defaults всех трёх операций и формы с частично заданными аргументами; старые и новые реализации не объявлены byte-identical. `swapNv()` описан как конверсия в старый NV21-label перед swap, с маршрутом `applyFormat(nv12)` → `applyChromaSwap()` для других форматов. Breaking changes CHANGELOG теперь ссылается на MIGRATION.md.
- Сверка кода: `git show 0.2.4:lib/src/yuv/impl/io/yuv_image.dart` и `.../impl/web/yuv_web.dart` подтверждают `gaussianBlur(radius: 2, sigma: 2)`, `boxBlur(radius: 10)`, `meanBlur(radius: 2)`; оба `swapNv()` конвертируют формат, отличный от NV21, через `toYuvNv21()`. Старый `copy(blank: true)` в обоих backend передавал сохранённые pixelStride в конструктор без planes, поэтому произвольный row padding терялся. Текущие `YuvImage.i420` и `YuvPlane` сверены по `lib/src/yuv/yuv.dart` и `lib/src/yuv/shared/yuv_plane.dart`.
- Расширенная старая API-фикстура: `flutter analyze` — PASS, No issues found (`C:\Users\Oleg-T\AppData\Local\Temp\fix9-api-fixture-0eb5f9ef21b84887ac9a021909818854\old-app`, `analyze-rework.log`); добавлены формы blur с defaults/частичными аргументами, `swapNv()` на NV21 и I420 и blank-copy для pixelStride 2.
- Мигрированная полная API-фикстура собрана по MIGRATION.md из старого файла, сохраняя вызовы всех таблиц и добавленные варианты rework; `flutter analyze` — PASS (scratch `C:\Users\Oleg-T\AppData\Local\Temp\fix9-rework-current`, `analyze.log`). Три Verify-команды из документа проверены без изменения шаблонов: старая API-фикстура вернула совпадения (`rg` exit 0), мигрированная — совпадений нет (`rg` exit 1) для каждой; ошибок `rg` exit 2 не было. Отдельная миграция подагентом не выполнялась согласно ограничению Engineer 0.
- Runtime scratch: `flutter test` — PASS, 2 теста. Padding-preserve вернул rowStride `[8,4,4]`, pixelStride `[1,1,1]`, нулевые bytes; factory без `preserve` вернула rowStride `[4,2,2]`. Pixel gaps: preserve сохранил `(rowStride,pixelStride,length)` `[(12,2,48),(6,2,12),(6,2,12)]`; packed дал `[(4,1,16),(2,1,4),(2,1,4)]`. Scratch: `C:\Users\Oleg-T\AppData\Local\Temp\fix9-rework-current` (`analyze.log`, `test.log`).
- Чистый архив коммита `46e814d7dda87db469ed992730f95022a717ddc4` создан через `git archive`; `MIGRATION.md` присутствует. На архиве `flutter pub publish --dry-run` — exit 0, 0 warnings, 1 version hint (предыдущая опубликованная версия 0.2.4); лог: `C:\Users\Oleg-T\AppData\Local\Temp\fix9-publish-run-1004\publish-dry-run.log`. Архив: `C:\Users\Oleg-T\AppData\Local\Temp\fix9-publish-run-1004.zip`.
- `git diff --cached --check` — PASS перед коммитом; коммит реализации: `46e814d7dda87db469ed992730f95022a717ddc4` (`Clarified migration behavior and examples`). Изолированная агентная миграция не выполнялась согласно бюджету Engineer 0. Пробы не требуются (`Probe: none`).

#### Executor Report — Rework 2

- Исправлен повторный отзыв: пример blank-image теперь принимает I420 `source` и строит каждый zeroed plane из `source.planes` по его `height`, `rowStride` и `pixelStride`; затем создаёт `YuvImage.i420(source.width, source.height, ..., layout: YuvPlaneLayout.preserve)`. Убраны размеры 4×4 и вручную заданные buffers из рецепта.
- Точный fenced-сниппет извлечён из `MIGRATION.md` без ручного переписывания и вставлен в вызываемую функцию scratch-теста. `flutter analyze` — PASS; `flutter test test/review3-exact-snippet_test.dart` — PASS, 2 теста. Проверены: 4×4 с rowStride `[8,4,4]`/pixelStride `[1,1,1]`; 6×6; 4×4 с rowStride `[12,6,6]`/pixelStride `[2,2,2]`. Для каждой плоскости сравнивались height, rowStride, pixelStride и длина bytes с источником; все выходные bytes — нулевые. Packed-контроль без `preserve` дал `[4,2,2]`, pixelStride `[1,1,1]`, длины `[16,4,4]`.
- Scratch: `C:\Users\Oleg-T\AppData\Local\Temp\fix9-rework-current`; логи `review3-analyze.log` и `review3-exact-snippet.log`. Publish dry-run необходимо повторить на чистом архиве SHA с этим исправлением; предыдущий результат относится к старой версии примера.

#### Review — повторное ревью 04.10.2026

- **Вердикт: REWORK → TODO.** Проверен диапазон `8bab4a74e6fa0f41097832e8381100999210efc4..7151e9700c7fbac9dd7e6e4a413366151474763e`; реализация — `46e814d7dda87db469ed992730f95022a717ddc4`, следующие два коммита меняют только карточку. Изменения прочих задач рабочего дерева не входят в ревью.
- **Закрыто:** defaults/частичные аргументы blur, прежняя автоматическая конверсия `swapNv()`, ссылка CHANGELOG. Обязательный `layout: preserve` добавлен, но новый пример не реализует заявленное сохранение layout источника (замечание ниже).
- **P2 — MIGRATION.md:68–77, пример blank-image берёт размеры source, но фиксирует плоскости для 4×4.** `source.width/height` сочетаются с константами `(4,8,1), (2,4,1), (2,4,1)` вместо характеристик `source.planes`. Точный сниппет, извлечённый из документа без переписывания, на I420 6×6 бросает `ArgumentError`. На I420 4×4 с rowStride `[12,6,6]` и pixelStride `[2,2,2]` возвращает `[8,4,4]` и `[1,1,1]`: исходный layout потерян. Исполнительские `examples.dart` и runtime-тесты используют свои константные варианты и этот дефект не проверяют.
- **Конкретная доработка:** обозначить, что `source` — I420, и заменить константные planes на `source.planes.map((plane) => YuvPlane(plane.height, plane.rowStride, plane.pixelStride))`; YuvPlane без bytes уже создаёт нулевой buffer. Сохранить размеры source и `layout: YuvPlaneLayout.preserve`. Это пример сохранения выбранного source-layout, а не byte-equivalent замена старого blank-copy. Другой допустимый вариант — полностью самостоятельный пример фиксированного 4×4, явно названный примером заданного layout; однако для закрытия исходного требования всё равно показать рецепт из характеристик source.
- **Проверка исправления:** в scratch копировать точный окончательный fenced-сниппет MIGRATION.md в вызываемую функцию (не писать похожую реализацию отдельно). Запустить её для I420 4×4 с padding `[8,4,4]`, I420 6×6 и I420 4×4 с rowStride `[12,6,6]` / pixelStride `[2,2,2]`; во всех трёх случаях assert размеров, всех `height/rowStride/pixelStride/bytes.length` по source и нулевых bytes. Анализировать тот же сниппет. Сохранить контроль упаковывания без preserve. Остальные прошедшие проверки не расширять до backend-матрицы. Обновить dry-run на чистом SHA с исправленным документом и записать новый SHA/логи; старый результат относится к старому примеру.
- **Независимо воспроизведено:** обе расширенные фикстуры `flutter analyze --no-pub` — PASS; исполнительские runtime-тесты — PASS, 2/2; точные Verify-команды на старой фикстуре — exit 0 каждая, на мигрированной — exit 1 каждая; `git diff --check 8bab4a7..HEAD` — PASS. `flutter pub publish --dry-run` на export реализации — exit 0, **0 warnings / 1 hint**, MIGRATION.md в публикуемом списке; текст документа export совпадает с текущим после нормализации CRLF.
- **Логи:** старая фикстура `.../fix9-api-fixture-0eb5f9ef21b84887ac9a021909818854/old-app/review2-analyze.log`; новая — `.../fix9-rework-current/review2-analyze.log`, `review2-test.log`; publish — `.../fix9-publish-run-1004/review2-publish.log` (все каталоги под `C:/Users/Oleg-T/AppData/Local/Temp`). Независимое воспроизведение дефекта: `C:/Users/Oleg-T/AppData/Local/Temp/fix9-review-73e5cfcec9ec4fce8607c14d84ba7680/exact_snippet_test.dart`, `review2-exact-snippet.log`. Два негативных теста PASS подтверждают дефект рецепта, не его исправность. Процессы завершены; Probe none; делегирования не было.

#### Executor Report — Rework 3

- По замечанию P2 заменён фиксированный список плоскостей на `source.planes.map((plane) => YuvPlane(plane.height, plane.rowStride, plane.pixelStride))` для I420 source; пропущенный bytes-аргумент создаёт zero-filled planes. Пример сохраняет размеры source и передаёт `layout: YuvPlaneLayout.preserve`.
- Проверен без переписывания точный fenced-сниппет из текущего `MIGRATION.md`: он извлечён автоматически и вызван на I420 4×4 с rowStride `[8,4,4]`, I420 6×6 и I420 4×4 с rowStride `[12,6,6]`/pixelStride `[2,2,2]`. `flutter analyze` — PASS; `flutter test test/review3-exact-snippet_test.dart` — PASS, 2 теста. Во всех сценариях сравнивались размеры и `height`, `rowStride`, `pixelStride`, длины buffers с source; выходные bytes нулевые. Packed-контроль без preserve — rowStride `[4,2,2]`, pixelStride `[1,1,1]`, lengths `[16,4,4]`.
- Scratch: `C:\Users\Oleg-T\AppData\Local\Temp\fix9-rework-current`; логи `review3-analyze.log` и `review3-exact-snippet.log`.
- Новый чистый export SHA `e0d23ee3f0538c1e451674a162ee458cf38d8fc0` проверен через `git archive`: `MIGRATION.md` присутствует в архиве и публикуемом списке. `flutter pub publish --dry-run` — exit 0, 0 warnings, 1 version hint о предыдущей версии 0.2.4; лог `C:\Users\Oleg-T\AppData\Local\Temp\fix9-publish-run-1004-r3\publish-dry-run.log`, архив `C:\Users\Oleg-T\AppData\Local\Temp\fix9-publish-run-1004-r3.zip`.
- Probe none. Полная backend-матрица и агентная миграция не требуются/не выполнялись.
