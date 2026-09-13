# yuv_ffi: план исправлений после аудита

Актуально для ветки `release/0.2.4`, commit `5f52fd1` и tag `0.2.4`.

Цель: устранить найденные release-блокеры, восстановить воспроизводимые проверки Web/native и подготовить следующий исправляющий релиз. Текущий `0.2.4` нельзя считать готовым к публикации, пока задачи уровня P0/P1 не приняты.

## Общий чеклист

| Готово | ID | Владелец | Приоритет | Статус | Зависит от | Краткое описание |
|---|---|---|---|---|---|---|
| [ ] | YUV-01 | Terra | P0 | READY FOR REVIEW | — | Починить компиляцию Web JS interop и привести platform-specific helper к структуре проекта |
| [ ] | YUV-02 | Luna | P0 | BLOCKED | YUV-01 | Сделать Web CI реальным обязательным gate, а не VM-запуском со skip |
| [ ] | YUV-03 | Luna | P1 | TODO | — | Исправить потерю Y-плоскости в native `swapNv()` и закрыть регресс тестами |
| [ ] | YUV-04 | Opus | P0 | BLOCKED | YUV-03, YUV-16 | Валидировать геометрию и planes до любого FFI-вызова |
| [ ] | YUV-05 | Opus | P0 | BLOCKED | YUV-04 + разрешение на C | Исправить native stride/odd-size безопасность конверсий и обновить WASM |
| [ ] | YUV-06 | Terra | P1 | BLOCKED | разрешение на C | Восстановить загрузку и упаковку native-библиотеки на Linux/macOS |
| [ ] | YUV-07 | Opus | P2 | BLOCKED | YUV-04 | Сделать сериализацию проверяемой, транзакционной и одинаковой на IO/Web |
| [ ] | YUV-08 | Luna | P2 | BLOCKED | YUV-01, YUV-04, YUV-15 | Восстановить Web parity для padded BGRA и публичного tight-buffer контракта |
| [ ] | YUV-09 | Luna | P2 | BLOCKED | YUV-01, YUV-02, YUV-05…YUV-08, YUV-13, YUV-14, YUV-17 | Синхронизировать README, platform matrix и локальный analyzer workflow |
| [ ] | YUV-10 | Terra | P1 | TODO | — | Подготовить независимый эталон и manifest для `test_pattern_512.png` |
| [ ] | YUV-11 | Luna | P1 | BLOCKED | YUV-10 | Прогнать по эталону каждую публичную операцию на native backend |
| [ ] | YUV-12 | Luna | P1 | BLOCKED | YUV-01, YUV-10 | Прогнать ту же матрицу по эталону на реальном Web/WASM backend |
| [ ] | YUV-13 | Terra | P1 | BLOCKED | YUV-11, YUV-12 | Проверить полноту матрицы и оформить все падения в `failed-test-cases.md` |
| [ ] | YUV-14 | Luna | P1 | BLOCKED | YUV-01, YUV-03 | Убрать выравнивающий хвост из IO/Web `getBytes()` |
| [ ] | YUV-15 | Terra | P1 | BLOCKED | YUV-04 | Сделать BGRA-конструкторы согласованными и безопасными для padded plane |
| [ ] | YUV-16 | Opus | P1 | BLOCKED | YUV-03 | Обеспечить exception-safe освобождение всех последовательных native allocations |
| [ ] | YUV-17 | Luna | P2 | BLOCKED | YUV-01 | Добавить отдельный analyzer/build gate для package `example/` |
| [ ] | YUV-19 | Terra | P1 | TODO | — | Починить кэш экземпляра `YuvFfiBindings` в native loader |
| [ ] | YUV-20 | Opus | P1 | BLOCKED | YUV-01 | Сделать ключ image cache корректным для мутабельного `YuvImage` |
| [ ] | YUV-21 | Opus | P1 | BLOCKED | YUV-01, YUV-19 | Зафиксировать retry/error/lazy-init контракт IO и Web |
| [ ] | YUV-18 | Terra | P0 | BLOCKED | YUV-01…YUV-17, YUV-19…YUV-21 | Провести финальную кроссплатформенную приёмку и подготовить `0.2.5` |

## Статусы

- `TODO` — задача изолирована, её зависимости выполнены и модель может взять её в работу.
- `IN PROGRESS` — модель начала работу; одновременно у задачи один исполнитель.
- `BLOCKED` — не выполнена зависимость или отсутствует обязательное разрешение.
- `READY FOR REVIEW` — реализация закончена, модель приложила результат и проверки; требуется независимое ревью.
- `DONE` — инженер проверил diff, тесты и фактическое поведение и принял задачу.
- `REJECTED` — реализация возвращена с конкретным списком замечаний; после исправлений снова `READY FOR REVIEW`.

Модель не ставит своей задаче `DONE`. После реализации она меняет статус на `READY FOR REVIEW` и заполняет секцию «Результат». Статус `DONE` выставляется только после независимой проверки.

## Общие решения и ограничения

1. Рассинхрон имени `NV21` и фактического UV-порядка принят как установленный compatibility contract:
   - публичное имя `nv21` пока сохраняется;
   - текущий UV/NV12-like порядок байтов сохраняется;
   - нельзя «исправлять» цвета слепой перестановкой U/V;
   - любые тесты и комментарии должны явно отличать публичное legacy-имя от фактического порядка chroma.
2. Web остаётся частичным WASM backend. Исправление компиляции и тестов не означает автоматическую feature parity с native.
3. Нельзя читать, анализировать или включать в scope любые `build/` директории.
4. Нельзя вручную редактировать `lib/src/functions/bindings/yuv_ffi_bingings.dart`. При изменении ABI обновить header/`ffigen.yaml` и выполнить генерацию.
5. Любое изменение файлов `src/**/*.c`, `src/**/*.h` или platform C-forwarders запрещено до отдельного явного разрешения владельца. До него YUV-05 и C-часть YUV-06 остаются `BLOCKED`.
6. Не совмещать соседний рефакторинг с исправлением дефекта. Каждый commit должен содержать только одну задачу.
7. Не удалять локальные `_tmp_*` файлы без отдельного подтверждения владельца.
8. Не создавать tag и не выполнять push без отдельного запроса.
9. Эталон для `test/assets/test_pattern_512.png` нельзя генерировать через тестируемый native/WASM код `yuv_ffi`: иначе одинаковая ошибка окажется и в expected, и в actual.
10. Каждый новый провал эталонного теста регистрируется в `failed-test-cases.md`. Исправление не удаляет запись: она переводится в `RESOLVED` со ссылкой на commit и повторный прогон.

## Общий Definition of Done для каждой задачи

- Реализован только scope карточки; чужие и несвязанные изменения сохранены.
- Добавлен regression test, который падает на `0.2.4` и проходит после исправления, если дефект тестируем автоматически.
- Выполнены все команды из секции «Проверка» с записанными exit code и фактическим числом тестов.
- Для Web отдельно подтверждено, что тесты исполнялись с `kIsWeb == true`, а не прошли через skip-ветку.
- Для native отдельно записаны ОС, архитектура и источник загруженной библиотеки; локальный игнорируемый `yuv_ffi.dll` не считается доказательством clean-checkout CI.
- `flutter analyze` не содержит новых diagnostics.
- `dart format --output=none --set-exit-if-changed` проходит для изменённых Dart-файлов.
- `git diff --check` проходит.
- `git status --short` приложен к результату.
- Публичный `NV21`/UV compatibility contract не изменён.
- Изменения native C либо отсутствуют, либо в результате приведена ссылка на явное разрешение владельца.

## Шаблон результата модели

Скопировать в конец своей карточки:

```text
Статус: READY FOR REVIEW
Commit: <hash или "не создавался">
Изменённые файлы:
- <path>

Что сделано:
- <кратко по фактам>

Проверки:
- <команда> — exit <code>, <результат/число тестов>

Ручная проверка:
- <ОС/браузер/архитектура и наблюдаемый результат>

Остаточные риски:
- <нет или конкретный риск>

Native C permission:
- <не требовалось / ссылка на разрешение>
```

---

## YUV-01 — восстановить компиляцию Web JS interop

- Владелец: Terra
- Приоритет: P0 / release blocker
- Статус: READY FOR REVIEW
- Зависимости: нет
- Scope:
  - `lib/src/web/js_util_compat.dart`
  - `lib/src/loader/impl/wasm_loader_web.dart`
  - `lib/src/yuv/impl/web/yuv_web.dart`
  - `example/lib/widgets/impl/js_util_compat.dart`
  - Web-only импорты, непосредственно затронутые переносом helper

### Проблема

Настоящая Web-компиляция падает:

```text
Functions converted via 'toJS' require a statically known function type,
but Type 'Function' is not a precise function type.
```

Причина — `allowInterop(Function function) => function.toJS`: статический тип `Function` недостаточен для `dart:js_interop`. Обычный analyzer этого не обнаруживает; ошибка появляется в Web compiler. Такой же helper продублирован в `example/`.

Дополнительно package helper лежит в `lib/src/web/js_util_compat.dart`, хотя platform-dependent реализации по `AGENTS.md` должны находиться под `impl/` и иметь суффикс `_web`.

### Зафиксированное решение

1. Удалить нетипизированный `allowInterop(Function)`.
2. В местах передачи callback в JS использовать точно типизированные функции и преобразовывать в JS только после того, как сигнатура известна компилятору.
3. Не маскировать проблему через `dynamic`, `as Function` или отключение compiler diagnostics.
4. Переместить package-specific interop helper под `impl/` и дать файлу суффикс `_web`; обновить только необходимые импорты.
5. Исправить тот же контракт в `example/`. Допустимо переиспользовать один package helper, если это не расширяет публичный API.
6. Не объявлять Web feature-complete: задача устраняет compile blocker, а не закрывает весь WASM parity backlog.

### DoD

- `flutter test --platform chrome test/web` успешно компилируется и доходит до реальных Web-тестов.
- Ни один Web-файл не сообщает `web-only ... skipped on non-web runtime` при Chrome-запуске.
- `example/` успешно компилируется для Web.
- Не осталось нетипизированных обёрток `allowInterop(Function)`.
- Platform-specific package helper соответствует `impl/` + `_web` правилу.
- Native VM tests не регрессировали.

### Проверка

```powershell
flutter analyze lib test
flutter test
flutter test --platform chrome test/web
Push-Location example
flutter analyze
flutter build web
Pop-Location
dart format --output=none --set-exit-if-changed lib example/lib test
git diff --check
git status --short
```

### Результат

Статус: READY FOR REVIEW
Commit: текущий YUV-01 task commit
Изменённые файлы:
- `lib/src/web/js_util_compat.dart` → `lib/src/web/impl/js_util_compat_web.dart`
- `lib/src/loader/impl/wasm_loader_web.dart`
- `lib/src/yuv/impl/web/yuv_web.dart`
- `example/lib/widgets/impl/js_util_compat.dart` → `example/lib/widgets/impl/js_util_compat_web.dart`
- `example/lib/widgets/impl/yuv_camera_preview_web.dart`

Что сделано:
- Удалён нетипизированный `allowInterop(Function)` в package и example.
- `locateFile` и `requestVideoFrameCallback` получили статически известные JS interop signatures перед `.toJS`.
- Package helper перенесён под `impl/` и получил суффикс `_web`.
- Web по-прежнему документируется как частичный WASM backend.

Проверки:
- `flutter analyze --no-pub lib test` — exit 0, no issues.
- `flutter test --no-pub` — exit 0, 30 tests passed; Web cases в этом VM-run были skipped ожидаемо.
- `flutter analyze --no-pub` из `example/` — exit 0, no issues.
- `flutter build web --no-pub` из `example/` — exit 0 за 44,4 s; были только существующие WASM dry-run warnings для `dart:html`.
- `dart format --output=none --set-exit-if-changed lib example/lib test` — exit 0 после format; production diff проверен отдельно.
- `git diff --check` — exit 0.

Ручная проверка:
- Исходный compiler diagnostic `Function.toJS` больше не возникает ни в package, ни в example Web build.
- `flutter test --platform chrome test/web` не завершился: runner завис на `loading` первого test file.
- Контрольный test только с `flutter_test` и `kIsWeb`, без импорта `yuv_ffi`, завис так же. Это отделено в F-007 и передано YUV-02.

Остаточные риски:
- F-001 остаётся `READY FOR RETEST`, а YUV-01 нельзя перевести в `DONE` до завершённого настоящего Chrome-run.
- Текущий host Chrome runner блокирует runtime evidence, хотя dart2js Web build компилируется успешно.

Native C permission:
- не требовалось; native C и generated bindings не менялись.

---

## YUV-02 — сделать Web CI настоящим обязательным gate

- Владелец: Luna
- Приоритет: P0 / release blocker
- Статус: BLOCKED
- Зависимости: YUV-01
- Scope:
  - `.github/workflows/ci.yml`
  - `README.md`, только команды запуска Web-тестов
  - небольшой Web-runner sentinel test
  - `failed-test-cases.md`, запись F-007

### Проблема

Текущий job `wasm-web-smoke` запускается только при `workflow_dispatch`. Команда `flutter test -d chrome` не выбирает Web test platform: локально все четыре файла выполнились на VM и прошли через ветку `if (!kIsWeb)`, дав ложный зелёный результат.

README повторяет ту же неверную команду. Поэтому заявления о Web parity не защищены CI.

После YUV-01 обнаружен дополнительный независимый блокер: даже минимальный test только с `flutter_test` и `kIsWeb`, без импорта `yuv_ffi`/WASM, запускает headless Chrome, но более 90 секунд остаётся на `loading`. Полный `test/web` ведёт себя так же. При этом `flutter build web` example проходит, поэтому это не прежняя ошибка `Function.toJS`; подробности зафиксированы в F-007.

### Зафиксированное решение

1. Сначала добавить/запустить минимальный Web sentinel и собрать verbose diagnostics F-007. Пока sentinel без package imports не работает, не менять production-код плагина в попытке починить runner.
2. Проверить совместимость установленного Chrome с Flutter Web test runner и сравнить локальный результат с чистым CI runner. Если зависание только локальное, записать точную границу доказательства и не объявлять его package defect.
3. Использовать `flutter test --platform chrome`, не `-d chrome`.
4. Запускать Web job как минимум на `pull_request` и push в релизные/основные ветки, а не только вручную.
5. Перед тестами пересобирать WASM из текущего C source и проверять наличие обоих артефактов.
6. Сохранить отдельные тестовые файлы или запускать весь `test/web`; выбранный вариант должен явно исполнить все четыре набора.
7. Sentinel обязан падать вне Web и защищать от ложного VM-запуска.
8. Обновить команды README на тот же фактический runner.

### DoD

- PR не может пройти при Web compile error или падении любого Web parity test.
- Минимальный sentinel реально исполняется в Chrome; F-007 получает `RESOLVED` либо подтверждённый local-only статус с успешным CI evidence.
- В CI-логе видны реальные названия Web-тестов, а не четыре skip-теста.
- Job запускается автоматически на PR.
- WASM собирается из того же commit, который тестируется.
- Команды README совпадают с CI.

### Проверка

```powershell
flutter test --platform chrome test/web/web_platform_sentinel_test.dart --reporter expanded
flutter test --platform chrome test/web/yuv_web_wasm_test.dart
flutter test --platform chrome test/web/wasm_parity_conversions_test.dart
flutter test --platform chrome test/web/wasm_parity_transforms_test.dart
flutter test --platform chrome test/web/wasm_parity_edge_cases_test.dart
git diff --check
git status --short
```

Также приложить ссылку на успешный автоматический CI run из PR/push, не на `workflow_dispatch`-only запуск.

### Результат

Не заполнен.

---

## YUV-03 — сохранить Y-плоскость в native `swapNv()`

- Владелец: Luna
- Приоритет: P1
- Статус: TODO
- Зависимости: нет
- Scope:
  - `lib/src/yuv/impl/io/yuv_image.dart`
  - `test/conversions_test.dart`
  - `test/web/wasm_parity_transforms_test.dart`, только parity assertion при необходимости

### Проблема

Native `swapNv()` создаёт пустой `nvYY`, вызывает C-функцию только для chroma и затем копирует Y из нулевого destination buffer. Подтверждённый runtime-результат для белого кадра:

```text
до swapNv:    [235, 235, 235, 235]
после swapNv: [0, 0, 0, 0]
```

Существующий тест делает два swap и сравнивает только `uPlane`, поэтому потерю luma не замечает. Web-код переносит Y явно и этим отличается от IO.

### Зафиксированное решение

1. В Dart IO wrapper явно копировать исходную Y-плоскость в destination; не читать её из незаполненного native destination buffer.
2. Не менять C-функцию `nvXX_to_nvYY` в этой задаче.
3. Проверять Y сразу после первого swap и после второго swap.
4. Проверить как исходный `nv21`, так и вызов `swapNv()` после конвертации из другого формата.
5. Не менять установленный UV/NV12-like compatibility contract.

### DoD

- Один `swapNv()` сохраняет Y byte-for-byte.
- Два `swapNv()` восстанавливают chroma и также сохраняют Y.
- Метод остаётся in-place и возвращает тот же объект.
- Добавленный regression test падает на `0.2.4` с фактическим `[0, 0, 0, 0]` и проходит после исправления.
- Native C не изменён.

### Проверка

```powershell
flutter test test/conversions_test.dart --plain-name "swapNv"
flutter test
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib/src/yuv/impl/io/yuv_image.dart test/conversions_test.dart
git diff --check
git status --short
```

### Результат

Не заполнен.

---

## YUV-04 — закрыть небезопасные входные данные до FFI boundary

- Владелец: Opus
- Приоритет: P0 / memory-safety blocker
- Статус: BLOCKED
- Зависимости: YUV-03, YUV-16
- Scope:
  - `lib/src/yuv/yuv.dart`
  - `lib/src/yuv/shared/yuv_plane.dart`
  - `lib/src/yuv/impl/io/yuv_image.dart`
  - `lib/src/yuv/impl/io/defs/yuv_def.dart`
  - соответствующие Web constructors для одинакового публичного контракта
  - новые focused tests

### Проблема

`YuvImage` принимает произвольные dimensions и `Iterable<YuvPlane>`, копирует список и сразу возвращает без проверки. `YUVDefClass` выделяет native buffers по фактической длине plane, а C обходит их по `image.width`, `image.height` и strides. Например, `YuvImage.i420(100, 100, planes: [YuvPlane(1, 1), ...])` способен привести к чтению/записи за выделенной памятью.

Отдельные проблемы контракта:

- не проверяются положительные width/height, pixelStride и rowStride;
- не проверяются точное число и порядок planes для BGRA/I420/NV;
- не проверяются plane height и минимальная длина строки;
- `YuvPlane` документирует исключение для короткого `bytes`, но фактически принимает короткий buffer и оставляет хвост нулевым;
- `assignFrom()` документирует полный overwrite, но короткий input даёт частичное обновление;
- часть ошибок защищена только `assert`, который исчезает в release.

### Зафиксированное решение

1. Ввести один shared validator для image geometry/plane layout, используемый IO и Web.
2. Проверять до любого FFI/WASM вызова:
   - `width > 0`, `height > 0`;
   - точное число planes: BGRA = 1, NV = 2, I420 = 3;
   - ожидаемую высоту каждой plane, включая `ceil(height / 2)` для chroma;
   - `pixelStride > 0` и минимальный `rowStride` с учётом последнего sample и количества байтов sample;
   - согласованность `bytes.length` и `height * rowStride`;
   - поддерживаемые конкретной операцией stride/layout варианты.
3. Невалидный публичный input должен завершаться предсказуемым `ArgumentError`/`FormatException` до native allocation/call.
4. Привести `YuvPlane` constructor и `assignFrom()` к задокументированному full-buffer контракту: короткий и слишком длинный input не принимаются молча.
5. Не использовать `assert` как единственную защиту FFI boundary.
6. До добавления бросающей валидации принять YUV-16: все уже выделенные native resources должны освобождаться, если следующий constructor/allocation бросит.
7. Не менять C в этой задаче. Layout, который пока невозможно безопасно обработать без YUV-05, должен явно отклоняться до FFI.

### DoD

- Нельзя создать или загрузить `YuvImage` с несовместимыми dimensions/planes.
- Все намеренно невалидные cases бросают Dart exception и не завершают test process аварийно.
- IO и Web принимают/отклоняют одинаковую геометрию.
- Валидные padded planes, которые реально поддерживаются, продолжают работать.
- Тесты покрывают нулевые/отрицательные dimensions, неверное число planes, короткую plane, неверные strides и mismatch plane height.
- Невалидный кадр не оставляет native allocations даже при исключении из второго constructor/allocation; это подтверждено YUV-16.
- Валидный padded BGRA layout не классифицируется как невалидный и передаётся в YUV-15 без неясного `RangeError`.
- Native C и generated bindings не изменены.

### Проверка

```powershell
flutter test test/yuv_plane_validation_test.dart
flutter test test/conversions_test.dart
flutter test
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

Если имя нового test-файла выбрано другое, записать фактическую команду в результате.

### Результат

Не заполнен.

---

## YUV-05 — исправить native custom-stride и odd-size конверсии

- Владелец: Opus
- Приоритет: P0 / memory-safety blocker
- Статус: BLOCKED
- Зависимости: YUV-04 и отдельное явное разрешение владельца на изменение native C
- Scope:
  - `src/yuv/yuv420/yuv420_from_rgba.c`
  - `src/yuv/nv21/nv21_from_rgba8888.c`
  - `src/yuv/yuv420/yuv420_to_nv21.c`
  - `src/yuv/nv21/nv21_to_420.c`
  - `src/yuv/nv21/nv21_to_nv12.c`
  - связанные headers только при необходимом ABI change
  - IO/Web wrappers, WASM export list и generated bindings только если изменился ABI
  - native и Web regression tests

### Проблема

`fromRgba8888()` публично требует tight input длиной `width * height * 4`, но native YUV implementations вычисляют адрес строки RGBA через Y-plane stride. При padded/custom Y stride это чтение за границами входного buffer.

I420↔NV conversion делает raw `memcpy(height * sourceYRowStride)` в destination с собственным, потенциально меньшим stride. Это может переписать native heap.

Odd-size support также непоследователен: Dart выделяет chroma через `ceil`, а несколько C conversion loops используют `width >> 1` и `height >> 1`; крайняя строка/колонка остаётся неинициализированной или усредняется делением на четыре при меньшем количестве реальных pixels.

`nvXX_to_nvYY` принимает один stride сразу для source и destination, что небезопасно при разных layouts.

### Зафиксированное решение

1. После получения разрешения исправить tight RGBA indexing: source RGBA row stride равен `width * 4` и не зависит от destination Y stride.
2. Копировать Y между разными layouts построчно/по sample с отдельными source и destination strides; не использовать raw memcpy размера source buffer в меньший destination.
3. Для chroma последовательно использовать ceil-размеры и делить сумму edge-блока на фактическое количество pixels.
4. Для `nvXX_to_nvYY` передавать разные source/destination strides либо выполнять безопасную перестановку в wrapper; один stride для двух buffers не сохранять.
5. Если ABI изменился:
   - обновить header;
   - обновить WASM call signature/export;
   - выполнить `flutter pub run ffigen --config ffigen.yaml`;
   - не редактировать generated bindings вручную.
6. Сохранить установленный UV/NV12-like byte order несмотря на legacy-имя `nv21`.
7. Пересобрать `assets/wasm/yuv_ffi.js` и `.wasm` из исправленного C source.

### DoD

- ASan/эквивалентная native проверка не находит OOB для custom stride и odd dimensions.
- Tight RGBA input корректно конвертируется в padded destination planes.
- I420↔NV корректно работает при разных source/destination strides.
- Размеры `1x1`, `3x5`, `127x255` имеют детерминированные Y/chroma planes на native и Web.
- Native и WASM результаты находятся в зафиксированном numeric tolerance.
- Сгенерированные WASM artifacts соответствуют текущему C commit.
- В результате приложено явное разрешение на C-изменения.

### Проверка

```powershell
flutter pub run ffigen --config ffigen.yaml
flutter analyze lib test
flutter test
flutter test --platform chrome test/web
git diff --check
git status --short
```

Дополнительно выполнить native sanitizer/build tests на доступной toolchain и записать точные команды, ОС, compiler и результат. Простого Windows-теста с локальным игнорируемым DLL недостаточно.

### Результат

Не заполнен.

---

## YUV-06 — восстановить Linux/macOS packaging и runtime loading

- Владелец: Terra
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: отдельное явное разрешение владельца на изменение macOS C-forwarders
- Scope:
  - `lib/src/loader/impl/loader_io.dart`
  - `linux/CMakeLists.txt`
  - `macos/yuv_ffi.podspec`
  - `macos/Classes/**`
  - CI native build/smoke matrix
  - platform support section README только после фактической проверки

### Проблема

Linux и macOS loader открывает `native/src/build/libyuv_ffi.*`. Такого runtime path нет в публикуемом package/application bundle. На Linux CMake уже объявляет bundled target, который должен загружаться по имени установленной библиотеки. На Apple symbols должны находиться в process либо в корректно упакованном framework/library.

У macOS есть только один forwarder `macos/Classes/yuv_ffi.c`, подключающий агрегатор `src/yuv_ffi.c`, который сам содержит только include header. Реализации YUV/BGRA операций в macOS pod target не включены.

Текущий успешный Windows `flutter test` зависит от локального игнорируемого `yuv_ffi.dll`; это не clean-checkout доказательство.

### Зафиксированное решение

1. Использовать platform loading contract:
   - Android/Linux — установленное имя `libyuv_ffi.so`;
   - Windows — `yuv_ffi.dll`;
   - iOS/macOS — symbols текущего process, если library статически/динамически связана pod target.
2. Добавить macOS source forwarding, эквивалентный полному проверенному iOS набору, либо другой корректный podspec source layout.
3. Не дублировать одни и те же C translation units дважды.
4. Добавить clean-checkout CI:
   - Linux и Windows: build + runtime smoke;
   - macOS: build + runtime smoke;
   - Android/iOS: как минимум plugin/example build, runtime — если инфраструктура позволяет.
5. Smoke должен вызвать `YuvFfi.ensureInitialized()` и одну реальную BGRA/YUV операцию, а не только проверить существование файла.
6. Не использовать и не публиковать локальный root `yuv_ffi.dll` как обходной путь.

### DoD

- Linux и macOS example/минимальный host собираются из clean checkout.
- `ensureInitialized()` на Linux/macOS не обращается к `native/src/build/...`.
- Все используемые generated binding symbols находятся в runtime library/process.
- Smoke conversion успешно выполняется на Windows, Linux и macOS.
- Mobile build checks проходят.
- CI не зависит от локальных бинарников разработчика.
- В результате приложено разрешение на изменение macOS C-forwarders.

### Проверка

Приложить фактические команды каждой ОС. Минимальный набор:

```text
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build <platform>
<runtime smoke command>
git diff --check
git status --short
```

Не извлекать и не анализировать содержимое `build/`; использовать только exit code команд сборки/запуска.

### Результат

Не заполнен.

---

## YUV-07 — укрепить формат save/load

- Владелец: Opus
- Приоритет: P2
- Статус: BLOCKED
- Зависимости: YUV-04
- Scope:
  - `lib/src/loader/data_io.dart`
  - shared serialization codec при извлечении
  - IO/Web `YuvImage.load()` и `save()`
  - serialization tests

### Проблема

Публичная документация обещает `FormatException` для malformed payload, но текущий reader:

- защищён `assert`, исчезающим в release;
- проверяет общий buffer, а не надёжно контролируемый remaining range;
- полностью накапливает stream до разбора;
- доверяет JSON types, format name, dimensions, plane count и byte lengths;
- игнорирует поле `version`;
- меняет `_width`, `_height`, `_format` и `_planes` до успешного завершения parsing.

Ошибка в середине payload может оставить существующий объект частично изменённым и выбросить `RangeError`, `TypeError` или enum error вместо обещанного `FormatException`.

### Зафиксированное решение

1. Вынести один shared versioned codec, используемый IO и Web.
2. Парсить в локальный immutable draft; применять новое состояние только после полного разбора и YUV-04 validation.
3. Заменить asserts явными remaining-length checks.
4. Проверять JSON object, `version == 1`, известный format, положительные dimensions, ожидаемое число planes, metadata и точную длину plane bytes.
5. Все malformed/truncated/unsupported-version cases преобразовывать в `FormatException` с безопасным сообщением.
6. Не доверять заявленной длине до проверки против доступных bytes и валидированной геометрии.
7. Убрать безлимитное накопление произвольного stream: читать формат последовательно и ограничивать plane payload ожидаемым размером из metadata/geometry. Не вводить произвольный маленький global image limit без документированного решения.
8. Определить policy для trailing bytes; предпочтительно отклонять их как malformed payload.

### DoD

- Round-trip сохраняет format, dimensions, strides и bytes.
- Truncated header/JSON/plane, неизвестная версия/format, неверные types/counts/lengths и trailing garbage дают `FormatException`.
- При любой ошибке исходный `YuvImage` остаётся byte-for-byte и metadata-wise неизменным.
- IO и Web используют один формат и одинаковую validation policy.
- Нет проверки безопасности, основанной только на `assert`.

### Проверка

```powershell
flutter test test/yuv_serialization_test.dart
flutter test
flutter test --platform chrome test/web
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

### Результат

Не заполнен.

---

## YUV-08 — вернуть tight BGRA contract на Web

- Владелец: Luna
- Приоритет: P2
- Статус: BLOCKED
- Зависимости: YUV-01, YUV-04, YUV-15
- Scope:
  - `lib/src/yuv/impl/web/yuv_web.dart`
  - `test/web/wasm_parity_edge_cases_test.dart`
  - при необходимости shared row-repack helper

### Проблема

Публичный `toBgra8888()` обещает длину всегда `width * height * 4`. Native implementation уже repack-ит padded BGRA rows. Web для `bgra8888` возвращает копию всей `yPlane.bytes`, поэтому при `rowStride > width * 4` возвращает padding и нарушает контракт. `YuvImageWidget` затем отклоняет такой buffer по размеру.

Web edge tests покрывают padded I420/NV, но не padded BGRA.

### Зафиксированное решение

1. Повторить native semantics: при tight rowStride вернуть copy, при padding построчно скопировать только `width * 4` bytes.
2. Не менять исходную plane и не возвращать view на mutable backing buffer.
3. Добавить Web test с различимыми padding bytes, проверяющий и длину, и точный порядок pixels.
4. Добавить widget-level regression либо доказать существующим тестом, что repacked buffer декодируется.

### DoD

- Web `toBgra8888()` всегда возвращает ровно `width * height * 4` bytes.
- Padding не попадает в результат.
- Native/Web padded BGRA semantics совпадают.
- Реальный Chrome test проходит; VM skip не засчитывается.

### Проверка

```powershell
flutter test --platform chrome test/web/wasm_parity_edge_cases_test.dart
flutter test test/conversions_test.dart --plain-name "padded BGRA"
flutter test test/yuv_image_widget_test.dart
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

### Результат

Не заполнен.

---

## YUV-09 — синхронизировать документацию и локальные quality gates

- Владелец: Luna
- Приоритет: P2
- Статус: BLOCKED
- Зависимости: YUV-01, YUV-02, YUV-05, YUV-06, YUV-07, YUV-08, YUV-13, YUV-14, YUV-17
- Scope:
  - `README.md`
  - `analysis_options.yaml`
  - `CHANGELOG.md`, только draft следующего release entry
  - package metadata при необходимости

### Проблема

README предлагает dependency `^0.1.2`, но следующий пример использует `YuvFfi.ensureInitialized()`, добавленный только в `0.2.0`. Platform support заявляет Linux/macOS/Web без воспроизводимого доказательства. Web-команды используют неправильный `-d chrome`.

Полный локальный `flutter analyze` падает на игнорируемом `_tmp_pub_wasm_loader_web.dart`: Git ignore не является analyzer exclude. Targeted analysis tracked-кода при этом проходит.

### Зафиксированное решение

1. Обновить install snippet на фактическую поддерживаемую следующую версию; ожидаемый patch release — `^0.2.5` после YUV-18.
2. Описать `NV21` как legacy API name с установленным UV/NV12-like behavior, без попытки переименования в этом patch release.
3. Platform matrix должна отражать только фактически подтверждённые build/runtime checks; Web по-прежнему обозначить partial.
4. Заменить все Web test commands на `--platform chrome`.
5. Добавить узкий analyzer exclude для root `_tmp_*.dart`, не исключая обычный source/test code и не удаляя пользовательские временные файлы.
6. Добавить наверху CHANGELOG draft следующего релиза только после определения фактически вошедших исправлений; синхронизацию версии завершает YUV-18.
7. Не заявлять sanitizer, platform runtime или Web parity без приложенного evidence.

### DoD

- Новый пользователь может установить указанную версию и выполнить Quick start.
- README-команды действительно запускают Web compiler/tests.
- Platform matrix не обещает неподтверждённую поддержку.
- `flutter analyze` из package root проходит при наличии текущего `_tmp_pub_wasm_loader_web.dart` и не анализирует его.
- CHANGELOG перечисляет только фактически принятые изменения.
- `pubspec.yaml` и верхняя версия CHANGELOG не остаются рассинхронизированы после YUV-18.

### Проверка

```powershell
flutter analyze
flutter test
flutter test --platform chrome test/web
flutter pub publish --dry-run
git diff --check
git status --short
```

### Результат

Не заполнен.

---

## YUV-10 — подготовить независимый эталон и manifest для `test_pattern_512.png`

- Владелец: Terra
- Приоритет: P1
- Статус: TODO
- Зависимости: нет
- Scope:
  - `test/assets/test_pattern_512.png` — только чтение, исходный файл не заменять
  - `test/reference/test_pattern_512/**` — новые эталонные данные
  - `test/helpers/reference/**` — независимые reference helpers
  - `tool/reference/**` — воспроизводимый генератор эталонов при необходимости
  - `pubspec.yaml`, только если reference generator требует отдельной dev dependency

### Проблема

Текущие tests загружают `test_pattern_512.png`, но большинство проверок подтверждают только форму результата, обратимость либо широкий MAE. Blur-операции являются smoke tests без сравнения с expected image. Часть expected-значений рассчитывается локальными helpers только для BGRA geometry, а единого набора эталонов, параметров и thresholds нет.

Если expected image создать вызовом самого `yuv_ffi`, тест законсервирует текущую ошибку. Поэтому native и Web должны сравниваться с третьим, независимым источником истины.

### Зафиксированное решение

1. Зафиксировать SHA-256 исходного `test/assets/test_pattern_512.png`, его decoded dimensions и RGBA color space assumptions.
2. Создать независимый pure-Dart reference implementation либо отдельный generator, который не импортирует `package:yuv_ffi` и не вызывает его native/WASM symbols.
3. Для каждой операции хранить в manifest:
   - стабильный case ID;
   - source SHA-256;
   - исходный и ожидаемый format/dimensions;
   - параметры операции;
   - expected artifact/hash;
   - способ сравнения (`exact` или numeric tolerance);
   - фиксированные `MAE`, maximum channel error и при необходимости percentile threshold;
   - обоснование tolerance.
4. Геометрические и byte-exact операции сравнивать строго. Lossy YUV conversion и Gaussian blur могут использовать tolerance, но threshold нельзя подбирать после просмотра actual конкретного backend.
5. Для visual output использовать один общий набор expected PNG/BGRA artifacts для native и Web. Нельзя создавать отдельный «эталон Web» и «эталон native».
6. Для raw YUV дополнительно хранить либо независимо рассчитанные plane bytes/hash, либо точные plane invariants; одной обратной конверсии в BGRA недостаточно.
7. Эталонные fixtures не должны перегенерироваться обычным test run. Обновление reference artifacts — отдельное осознанное действие с diff manifest и визуальным ревью.
8. Установленный legacy `nv21` label должен быть записан в manifest как UV/NV12-like compatibility order.

### Обязательная матрица эталонов

| Группа | Публичная операция | Форматы входа | Cases/параметры | Сверка |
|---|---|---|---|---|
| Construction | `YuvImage.bgra/i420/nv21` | BGRA, I420, `nv21` | tight и валидные padded planes | создание без исключения; metadata/bytes exact |
| Input | `fromRgba8888` | BGRA, I420, `nv21` | полный `512x512` RGBA | BGRA exact; YUV planes + decoded image по tolerance |
| Output | `toBgra8888` | BGRA, I420, `nv21` | tight и поддерживаемый padded layout | exact length; exact для BGRA, tolerance для YUV |
| Format | `toYuvBgra8888` | I420, `nv21` | in-place conversion | format/dimensions/identity + expected BGRA |
| Format | `toYuvI420` | BGRA, `nv21` | standard и поддерживаемый padded layout | Y/U/V planes + expected BGRA |
| Format | `toYuvNv21` | BGRA, I420 | standard и поддерживаемый padded layout | Y/UV planes + expected BGRA |
| Chroma | `swapNv` | `nv21`; I420 через documented conversion | один и два swap | Y exact; соседние chroma bytes exact; round-trip exact |
| Geometry | `crop` | BGRA, I420, `nv21` | внутренний rect, clamped rect, empty rect | dimensions + expected pixels/planes |
| Geometry | `rotate` | BGRA, I420, `nv21` | 0°, 90°, 180°, 270° | exact geometry; expected pixels/planes |
| Geometry | `flipHorizontally` | BGRA, I420, `nv21` | полный `512x512` | expected pixels/planes |
| Geometry | `flipVertically` | BGRA, I420, `nv21` | полный `512x512` | expected pixels/planes |
| Effect | `grayscale` | BGRA, I420, `nv21` | полный `512x512` | expected image; alpha exact |
| Effect | `blackwhite` | BGRA, I420, `nv21` | полный `512x512` | expected threshold image; alpha exact |
| Effect | `negate` | BGRA, I420, `nv21` | полный `512x512` | expected image; alpha exact |
| Blur | `gaussianBlur` | BGRA, I420, `nv21` | default; `radius: 3, sigma: 2` | expected image + predeclared tolerance |
| Blur | `boxBlur` | BGRA, I420, `nv21` | default; full frame; fixed rect | expected image; outside rect exact |
| Blur | `meanBlur` | BGRA, I420, `nv21` | default; full frame; fixed rect | expected image; outside rect exact |
| State | `copy` | BGRA, I420, `nv21` | normal и `blank: true` | deep-copy identity; bytes exact/zero |
| Bytes | `getBytes` | BGRA, I420, `nv21` | standard/padded | exact plane concatenation order |
| I/O | `save` / `load` | BGRA, I420, `nv21` | один chunk и fragmented stream | metadata/planes/bytes exact |
| Flutter | `toImage` | BGRA, I420, `nv21` | полный input | dimensions + decoded RGBA against expected |

Дополнительные odd-size/custom-stride cases из YUV-05 остаются обязательными, но могут использовать уменьшенный crop исходного изображения (`1x1`, `3x5`, `127x255`), чтобы не создавать искусственный input с другой цветовой статистикой.

### DoD

- Существует versioned manifest, покрывающий каждую строку обязательной матрицы.
- Reference generator не зависит от `yuv_ffi` прямо или транзитивно.
- Источник и каждый expected artifact имеют SHA-256.
- Повторный запуск generator без изменений даёт byte-identical manifest/artifacts.
- Все tolerance заданы до native/Web прогона и имеют объяснение.
- Эталоны вручную просмотрены минимум для original, crop, всех rotations, трёх effects и трёх blur-функций.
- Ни один existing golden не перезаписан без отдельного review.

### Проверка

```powershell
dart run tool/reference/generate_test_pattern_references.dart --check
flutter test test/reference_manifest_test.dart
flutter analyze test tool
git diff --check
git status --short
```

Имена generator/test допускается уточнить, но фактические команды должны быть записаны в результате.

### Результат

Не заполнен.

---

## YUV-11 — проверить все преобразования на native backend

- Владелец: Luna
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: YUV-10
- Scope:
  - `test/reference_native_conversions_test.dart`
  - shared test helpers из YUV-10
  - `failed-test-cases.md`, только регистрация фактических падений

### Проблема

Текущий native suite не проверяет каждую функцию на полном реальном изображении против независимого эталона. Особенно отсутствуют reference comparisons для blur и для большинства I420/`nv21` transforms. Успешный Windows run также использует локальный игнорируемый `yuv_ffi.dll`, поэтому его binary provenance необходимо фиксировать.

### Зафиксированное решение

1. Создать data-driven test suite по manifest YUV-10; не копировать одну и ту же проверку вручную для каждого format.
2. Для каждой строки обязательной матрицы выполнить case на BGRA/I420/`nv21`, где формат указан.
3. Каждый case должен проверять не только изображение, но и:
   - in-place identity/return contract;
   - format, dimensions и plane count;
   - row/pixel strides;
   - неизменяемые области и alpha;
   - отсутствие мутации source copy там, где ожидается новый объект.
4. Exact cases сравнивать byte-for-byte. Tolerance cases должны выводить MAE, maximum error, percentile и число pixels за threshold.
5. Каждый упавший case немедленно добавить в `failed-test-cases.md` по шаблону, включая commit, OS/arch и provenance native library.
6. Не менять production code в этой задаче. Найденные дефекты оформляются отдельными fix-задачами либо привязываются к YUV-03/YUV-05/YUV-06/YUV-07/YUV-08.
7. Не ослаблять reference threshold для получения зелёного результата.

### DoD

- В native suite присутствует отдельный case ID для каждой строки/варианта обязательной матрицы.
- Все cases используют исходный `test/assets/test_pattern_512.png` или задокументированный crop из него.
- Ни один expected result не получен из текущего native DLL.
- Все фактические падения отражены в `failed-test-cases.md`; количество падений в файле равно количеству уникальных failed case IDs последнего прогона.
- Результат содержит точный путь/способ сборки проверенной native library.
- Если suite не зелёный, задача всё равно может перейти в `READY FOR REVIEW` как завершённая диагностика, но не в `DONE` без полного failure log.

### Проверка

```powershell
flutter test test/reference_native_conversions_test.dart --reporter expanded
flutter analyze test
dart format --output=none --set-exit-if-changed test
git diff --check
git status --short
```

Повторить runtime suite на каждой доступной native desktop ОС. Результаты разных ОС не объединять в одну строку failure log, если actual metrics различаются.

### Результат

Не заполнен.

---

## YUV-12 — проверить все преобразования на Web/WASM backend

- Владелец: Luna
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: YUV-01, YUV-10
- Scope:
  - `test/web/reference_web_conversions_test.dart`
  - shared test helpers и manifest из YUV-10
  - `failed-test-cases.md`, только регистрация фактических падений
  - WASM artifacts только пересобрать, не исправлять production C/Web code

### Проблема

Текущие Web tests используют маленькие synthetic patterns и smoke assertions. Команда `-d chrome` запускала их на VM со skip. Нет доказательства, что каждая операция обрабатывает реальный `512x512` asset так же, как независимый эталон.

### Зафиксированное решение

1. Пересобрать WASM из текущего source перед прогоном.
2. Запустить ту же data-driven manifest matrix, что и YUV-11, через настоящий `--platform chrome`.
3. Использовать те же expected artifacts и thresholds, что native. Не создавать Web-specific expected images.
4. Проверять metadata, planes, in-place contract и exact/tolerance metrics так же, как в native suite.
5. Добавить явный Web environment assertion, чтобы case suite не мог пройти на VM.
6. Каждый failed case зарегистрировать в `failed-test-cases.md` с браузером, Flutter/Dart version, WASM source commit и metrics.
7. Не исправлять production behavior и не повышать tolerance в рамках этой задачи.

### DoD

- Все строки обязательной матрицы реально исполняются с `kIsWeb == true`.
- Native и Web используют одинаковые case IDs, input SHA и expected artifacts.
- В результате записано фактическое число executed/passed/failed cases; skip не засчитывается как executed.
- Все падения полностью отражены в `failed-test-cases.md`.
- WASM artifacts однозначно связаны с тестируемым source commit.
- Если suite не зелёный, задача может перейти в `READY FOR REVIEW` только при полном failure log.

### Проверка

```powershell
flutter test --platform chrome test/web/reference_web_conversions_test.dart --reporter expanded
flutter test --platform chrome test/web
flutter analyze test
dart format --output=none --set-exit-if-changed test
git diff --check
git status --short
```

Перед командами выполнить `tool/wasm/build_wasm.sh` в поддерживаемом shell и записать exact command/exit code.

### Результат

Не заполнен.

---

## YUV-13 — сверить покрытие и оформить проваленные test cases

- Владелец: Terra
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: YUV-11, YUV-12
- Scope:
  - `failed-test-cases.md`
  - test manifest и результаты YUV-11/YUV-12
  - `todo.md`, только добавление новых fix-задач/зависимостей при подтверждённом новом дефекте

### Проблема

Без отдельной сверки легко потерять failed case в консольном логе, объединить разные backend failures или объявить покрытие полным при отсутствии одной комбинации format/operation. Проваленные cases не должны растворяться в task comments.

### Зафиксированное решение

1. Сопоставить manifest с фактически выполненными native/Web case IDs.
2. Для каждого missing case вернуть YUV-11 или YUV-12 в `REJECTED`.
3. Для каждого failed case создать или обновить отдельную запись в `failed-test-cases.md`.
4. Не объединять падения с разной root cause в одну запись. Один case на двух backends допускает общий failure ID только при доказанной общей причине; backend evidence всё равно записывается отдельно.
5. Каждую запись связать с существующей fix-задачей. Для нового дефекта добавить в `todo.md` отдельную узкую карточку Terra/Luna с dependencies и DoD.
6. После исправления запись не удалять: поставить `RESOLVED`, указать fix commit и приложить повторный successful run.
7. Итоговая сводка должна содержать totals: manifest cases, native executed/passed/failed/skipped, Web executed/passed/failed/skipped, unresolved failure IDs.

### DoD

- Нет manifest case без native/Web результата либо явно документированной platform limitation.
- Числа в итоговой сводке сходятся с test runner logs.
- Каждый failed case имеет отдельную запись, owner/fix task и воспроизводимую команду.
- У failure entries есть expected, actual, metric delta и ссылки на артефакты/логи без включения `build/`.
- Все unresolved failures блокируют YUV-18.

### Проверка

```powershell
flutter test test/reference_native_conversions_test.dart --reporter expanded
flutter test --platform chrome test/web/reference_web_conversions_test.dart --reporter expanded
git diff --check
git status --short
```

Также выполнить механическую проверку уникальности case ID и наличия каждого failed ID в `failed-test-cases.md`; фактическую команду записать в результат.

### Результат

Не заполнен.

---

## YUV-14 — убрать мусорный хвост из `getBytes()`

- Владелец: Luna
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: YUV-01 и YUV-03, чтобы не править Web/IO implementations параллельно
- Scope:
  - `lib/src/yuv/impl/io/yuv_image.dart`
  - `lib/src/yuv/impl/web/yuv_web.dart`
  - shared helper для concatenation при необходимости
  - `test/conversions_test.dart`
  - `test/web/wasm_parity_edge_cases_test.dart`
  - reference matrix YUV-10…YUV-13
  - `failed-test-cases.md`, запись F-003

### Проблема

Оба backend собирают planes через `WriteBuffer`, после чего возвращают `allBytes.done().buffer.asUint8List()`. `WriteBuffer` может иметь выровненный backing buffer больше фактического `ByteData` view. Поэтому публичный API возвращает нулевой хвост, не принадлежащий ни одной plane.

Подтверждённый case:

```text
YuvImage.i420(3, 3)
sum(plane.bytes.length) = 25
getBytes().length       = 32
```

IO и Web одинаково ошибочны, поэтому сравнение backend друг с другом не обнаруживает дефект. Нарушена документация «all planes concatenated into a single byte buffer».

### Зафиксированное решение

1. Возвращать ровно сумму `plane.bytes.length`, без alignment/padding backing buffer.
2. Предпочтительно вынести platform-agnostic helper, который заранее выделяет `Uint8List(totalLength)` и последовательно копирует каждую plane через offset. Альтернатива с `ByteData` допустима только со срезом по `offsetInBytes` и `lengthInBytes`.
3. Возвращаемый buffer должен быть независимой копией: его изменение не меняет planes, изменение planes после вызова не меняет уже полученный buffer.
4. Порядок concatenation остаётся format order: BGRA/Y, I420 Y-U-V, legacy `nv21` Y-UV.
5. Не исправлять результат добавлением special-case только для нечётных dimensions.

### DoD

- Для `1x1`, `3x3`, `127x255` и `512x512` длина результата равна точной сумме длин planes.
- Результат byte-for-byte равен ручной последовательной конкатенации.
- Нет хвоста после последнего байта последней plane.
- Проверены BGRA, I420 и legacy `nv21`, включая padded planes после YUV-15.
- IO и Web проходят один и тот же contract test, но expected строится прямой конкатенацией, а не другим backend.
- F-003 переведён в `RESOLVED` только после native и настоящего Chrome retest.

### Проверка

```powershell
flutter test test/conversions_test.dart --plain-name "getBytes"
flutter test --platform chrome test/web/wasm_parity_edge_cases_test.dart --plain-name "getBytes"
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

### Результат

Не заполнен.

---

## YUV-15 — поддержать валидный padded BGRA plane одинаково на IO/Web

- Владелец: Terra
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: YUV-04
- Scope:
  - `lib/src/yuv/impl/io/yuv_image.dart`, BGRA constructor
  - `lib/src/yuv/impl/web/yuv_web.dart`, BGRA constructor
  - shared validation из YUV-04
  - `test/conversions_test.dart`
  - `test/web/wasm_parity_edge_cases_test.dart`
  - reference matrix YUV-10…YUV-13
  - `failed-test-cases.md`, запись F-004

### Проблема

В IO специализированный `YuvImage.bgra(...)` пытается repack-ить строки через `WriteBuffer`, затем передаёт весь выровненный backing buffer новому `YuvPlane`. Для валидного input:

```dart
YuvImage.bgra(2, 2, planes: [YuvPlane(2, 16, 4)]);
```

конструктор падает:

```text
RangeError (end): Invalid value: Not in inclusive range 0..16: 32
```

Web специализированный конструктор делегирует generic constructor и сохраняет padded plane, поэтому backend contracts расходятся. YUV-08 исправляет только выдачу tight buffer из `toBgra8888()` и не закрывает constructor semantics.

### Зафиксированное решение

1. Для переданного валидного BGRA plane сохранять его rowStride/pixelStride и делать глубокую копию без constructor-time repack.
2. Tight output является обязанностью `toBgra8888()` из YUV-08, а не причиной уничтожать layout исходной plane в constructor.
3. Специализированный `YuvImage.bgra` и generic `YuvImage(YuvFileFormat.bgra8888, ...)` должны иметь одинаковый validation/copy contract.
4. Невалидный layout должен давать заранее определённый `ArgumentError`, созданный shared validator, а не случайный `RangeError` из `sublist`/`setAll`.
5. `copy()` и `copy(blank: true)` должны сохранять padded metadata; blank copy заполняет весь allocated plane нулями.
6. Не менять C в этой задаче.

### DoD

- Приведённый `2x2`, `rowStride: 16`, `pixelStride: 4` case создаётся без исключения на IO и Web.
- Constructor сохраняет metadata и deep-copy semantics.
- `toBgra8888()` после YUV-08 возвращает только 16 pixel bytes без padding.
- Невалидные padded layouts дают одинаковый публичный exception на IO/Web.
- Tests покрывают специализированный и generic constructors, tight/padded/invalid layouts и copy variants.
- F-004 переведён в `RESOLVED` после native и Web retest.

### Проверка

```powershell
flutter test test/conversions_test.dart --plain-name "padded BGRA"
flutter test --platform chrome test/web/wasm_parity_edge_cases_test.dart --plain-name "padded BGRA"
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

### Результат

Не заполнен.

---

## YUV-16 — сделать native allocations exception-safe

- Владелец: Opus
- Приоритет: P1; prerequisite для бросающей валидации YUV-04 (P0), поэтому не ниже P1
- Статус: BLOCKED
- Зависимости: YUV-03, чтобы не менять IO implementation параллельно
- Scope:
  - `lib/src/yuv/impl/io/yuv_image.dart`
  - `lib/src/yuv/impl/io/defs/yuv_def.dart`
  - test-only allocator seam и focused tests
  - native C не менять

### Проблема

Несколько методов выделяют первый ресурс до входа в `try/finally`. Если следующий constructor/allocation бросает, уже выделенная native memory теряется:

| Метод | Первая успешная аллокация | Следующая потенциально бросающая операция |
|---|---|---|
| `crop` | `srcDef` | `YUVDefClass(dst)` |
| `rotate` | `srcDef` | создание `dstImage`, затем `YUVDefClass(dstImage)` |
| `swapNv` | `def` | `YuvImageImpl.nv21()`, затем `YUVDefClass(nvYY)` |
| `toBgra8888` | `def` | `calloc.allocate` для BGRA output |
| `toYuvI420` | `def` | создание destination / `YUVDefClass(i420)` |
| `toYuvNv21` | `def` | создание destination / `YUVDefClass(n21)` |
| `fromRgba8888` | `rgbaPtr` | `YUVDefClass.template(this)` |

Сам `YUVDefClass._` также делает несколько последовательных `calloc` и должен освободить struct/Y/U/V, если более поздняя аллокация бросит.

После YUV-04 constructors и validators начнут предсказуемо бросать на невалидной геометрии, поэтому латентные пути должны быть закрыты до включения новой валидации.

### Зафиксированное решение

1. Перестроить каждый multi-resource участок так, чтобы владение первым ресурсом сразу находилось внутри `try/finally` до следующей бросающей операции.
2. Использовать nullable handles/nested scopes либо маленький scoped allocation helper; `dispose()` вызывается ровно один раз для каждого успешно созданного ресурса.
3. Сделать construction `YUVDefClass` транзакционным: при ошибке на Y/U/V allocation освободить все ранее созданные pointers и struct.
4. Не ловить и не подменять исходное исключение после cleanup.
5. Добавить test-only allocator seam/counters, позволяющие детерминированно бросить на каждой N-й allocation и проверить баланс allocate/free. Не пытаться воспроизводить OOM реальным исчерпанием памяти.
6. Проверить success path на double-free и use-after-free.
7. Не менять native C и generated bindings.

### DoD

- Для каждого перечисленного метода test заставляет следующую allocation/constructor бросить и подтверждает нулевой outstanding allocation count.
- `YUVDefClass` освобождает частично созданное состояние при сбое на каждой внутренней allocation.
- Исходный exception type/stack не теряется.
- Success paths продолжают проходить под leak/double-free instrumentation.
- YUV-04 явно зависит от принятой YUV-16 и не активирует новые leak paths.

### Проверка

```powershell
flutter test test/native_allocation_safety_test.dart --reporter expanded
flutter test test/conversions_test.dart
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

Если allocator instrumentation требует platform-specific runner, записать точный runner, ОС и архитектуру.

### Результат

Не заполнен.

---

## YUV-17 — анализировать `example/` как отдельный package

- Владелец: Luna
- Приоритет: P2
- Статус: BLOCKED
- Зависимости: YUV-01
- Scope:
  - `.github/workflows/ci.yml`
  - `example/analysis_options.yaml`
  - `example/pubspec.yaml` / `example/pubspec.lock` только при необходимой согласованной dependency resolution
  - команды проверки в YUV-01/YUV-09

### Проблема

`example/` имеет собственный `pubspec.yaml` и `analysis_options.yaml`. Root-команда `flutter analyze lib test example/lib` рассматривает путь из контекста root package и не является эквивалентом `flutter analyze`, запущенному внутри example package.

Это особенно важно для `example/lib/widgets/impl/js_util_compat.dart`: там находится второй экземпляр Web compile blocker YUV-01. Root analyzer не является доказательством чистоты example.

### Зафиксированное решение

1. В CI добавить отдельные steps/job с `working-directory: example`.
2. Внутри `example/` выполнить собственные dependency resolution, `flutter analyze` и Web build.
3. Использовать tracked lockfile предсказуемо: если текущий SDK требует его обновления, diff должен быть осознанным и принадлежать только этой задаче; не оставлять побочный lockfile diff от root command.
4. Root checks и example checks показывать отдельно в handoff result.
5. Не считать успешный root `flutter analyze` доказательством example analysis.
6. После YUV-06 расширить example build matrix подтверждёнными native desktop/mobile targets, не дублируя platform job без причины.

### DoD

- CI из каталога `example/` выполняет `flutter analyze`.
- CI компилирует `example/` для Web и обнаруживает ошибки его JS interop helper.
- Локальная инструкция содержит отдельные root/example команды.
- Root и example analyzer используют каждый свой `analysis_options.yaml`.
- `example/pubspec.lock` не меняется неявно во время root quality gate.

### Проверка

```powershell
flutter analyze
Push-Location example
flutter pub get
flutter analyze
flutter build web
Pop-Location
git diff --check
git status --short
```

Приложить ссылку на CI run, где example steps видны отдельно.

### Результат

Не заполнен.

---

## YUV-19 — починить кэш экземпляра native bindings

- Владелец: Terra
- Приоритет: P1
- Статус: TODO
- Зависимости: нет
- Scope:
  - `lib/src/loader/impl/loader_io.dart`
  - focused test кэша bindings
  - `lib/src/functions/bindings/yuv_ffi_bingings.dart` не изменять

### Проблема

Кэш bindings не работает. Объявлено `YuvFfiBindings? _ffiBingings`, но записи в это поле нет нигде в `lib/`; геттер возвращает `_ffiBingings ?? YuvFfiBindings(library)`, то есть `??` вместо `??=`. Каждое обращение создаёт новый экземпляр и выбрасывает `late final` кэш символов, который сам генератор формирует корректно. В `lib/src/yuv/impl/io/yuv_image.dart` 40 обращений к `ffiBingings.*`.

Подтверждённый замер на Windows, один и тот же символ:

```text
uncached 300 lookups:  38923 us
cached   300 lookups:     12 us
```

### Зафиксированное решение

1. Исправить кэш на `_ffiBingings ??= YuvFfiBindings(library)`; экземпляр создаётся один раз на процесс.
2. Не вводить reset/reload seam только ради теста. Если такой seam появится в YUV-21, он обязан сбрасывать bindings вместе с library.
3. Не измерять время как pass/fail-критерий: абсолютные microbenchmark thresholds нестабильны на CI.
4. Не менять initialization/retry/exception policy — это отдельная YUV-21.
5. Не редактировать сгенерированные bindings; дефект находится исключительно в рукописном loader.
6. Не совмещать с YUV-06: пути загрузки библиотеки Linux/macOS остаются в scope YUV-06.

### DoD

- `_ffiBingings` фактически переиспользуется; повторные обращения не создают новый `YuvFfiBindings`.
- Регресс-тест фиксирует identity: N обращений к `ffiBingings` возвращают один и тот же экземпляр.
- Замер производительности остаётся диагностическим evidence и не используется как flaky assertion.
- Публичный API не расширен.
- Сгенерированные bindings не изменены.

### Проверка

```powershell
flutter test test/loader_io_test.dart
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

Если имя нового test-файла выбрано другое, записать фактическую команду в результате. Отдельно записать ОС, архитектуру и источник загруженной библиотеки. Benchmark, если запускался, привести отдельно без release-порога.

### Результат

Не заполнен.

---

## YUV-20 — корректный image cache key для мутабельного `YuvImage`

- Владелец: Opus
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: YUV-01 для обязательного реального Chrome retest; зависимости от YUV-19 нет
- Scope:
  - `lib/src/widgets/yuv_image_widget.dart`
  - `lib/src/yuv/yuv.dart` и IO/Web implementations для revision/identity seam
  - `lib/src/yuv/shared/yuv_plane.dart`, только для документирования/сигнализации мутаций
  - `test/yuv_image_widget_test.dart`
  - reference matrix YUV-10…YUV-13, строка `Flutter`/`toImage` при необходимости

### Проблема

`YuvImageProvider` наследует `ImageProvider`, но не переопределяет `==` и `hashCode`, а `obtainKey()` возвращает `this`. Подтверждено:

```text
two providers same image equal? false
hashCodes equal?                false
```

Ключом `PaintingBinding.instance.imageCache` служит сам провайдер, сравниваемый по идентичности. Следствие: каждый rebuild `YuvImageWidget` создаёт новый ключ, промахивается мимо кэша и заново выполняет полную конверсию в BGRA плюс `decodeImageFromPixels`.

Обратная сторона задачи важнее. `YuvImage` намеренно мутабельный: `blackwhite`, `crop`, `rotate`, `grayscale`, `negate`, blur-операции и все `toYuv*` изменяют объект in-place и возвращают `this`. Поэтому наивное равенство по `image` немедленно создаёт противоположный дефект: кэш начнёт отдавать устаревший кадр после in-place мутации того же экземпляра.

Из-за этого задача не сводится к добавлению `==`: требуется осознанное решение о том, что именно образует identity кадра. Дополнительно planes публично мутабельны через `YuvPlane.bytes`, `setPixel()` и `assignFrom()`. Один только revision внутри методов `YuvImage` такие изменения не увидит.

### Зафиксированное решение

1. Ввести в `YuvImage` монотонный revision counter и публичный `markDirty()` для изменений, выполненных напрямую через mutable plane API.
2. Все штатные мутирующие методы `YuvImage` увеличивают revision ровно один раз после успешного изменения bytes, format, dimensions или strides. Реальные no-op ветки revision не меняют.
3. `YuvPlane.setPixel()`/`assignFrom()` должны либо сигнализировать owning image автоматически, либо их документация обязана требовать последующий `image.markDirty()`. Прямая запись в `plane.bytes` всегда требует `markDirty()`, поскольку `Uint8List.operator[]=` перехватить нельзя без изменения публичного типа.
4. `YuvImageProvider` при создании сохраняет revision snapshot. Его `==` использует identity экземпляра изображения плюс snapshot; `hashCode` строится из `identityHashCode(image)` и snapshot. Нельзя читать живой revision в `hashCode` уже помещённого в cache ключа.
5. Не использовать содержимое planes как hash-источник: полный хэш кадра на каждый rebuild недопустим по стоимости.
6. Одинаково реализовать revision/`markDirty()` на IO и Web; не допускать расхождения widget-поведения между backend.
7. Сохранить публичную in-place mutation model. Расширение API методами `revision`/`markDirty()` допустимо и должно быть документировано как часть cache coherency contract.
8. Сохранить текущее поведение `evict` при ошибке декодирования.

### DoD

- Повторный build того же неизменённого кадра переиспользует закэшированный `ui.Image` и не выполняет повторную конверсию.
- После любой in-place мутации виджет показывает новый кадр, а не устаревший.
- `==`/`hashCode` согласованы: равные провайдеры имеют равный `hashCode`.
- Provider key хранит immutable revision snapshot; его `hashCode` не меняется после помещения в `ImageCache`.
- Revision изменяется для всех штатных мутирующих операций, включая `load()` и `fromRgba8888()`, только после успешного изменения.
- Прямая запись в `plane.bytes` с последующим `markDirty()` инвалидирует старый cache key; этот сценарий покрыт тестом и доксрокой.
- Widget-тест считает фактические вызовы conversion/decode seam и доказывает cache hit без мутации и обязательный refresh после мутации. Одного сравнения provider/hashCode недостаточно.
- Поведение одинаково на IO и в реальном Chrome.
- Публичная mutation model не изменена.

### Проверка

```powershell
flutter test test/yuv_image_widget_test.dart
flutter test
flutter test --platform chrome test/web
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

Для Web отдельно подтвердить, что тесты исполнялись с `kIsWeb == true`.

### Результат

Не заполнен.

---

## YUV-21 — зафиксировать контракт инициализации IO/Web

- Владелец: Opus
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: YUV-01 и YUV-19, чтобы сначала закрыть Web compile gate и не менять `loader_io.dart` параллельно
- Scope:
  - `lib/src/yuv_ffi_initializer.dart`
  - `lib/src/loader/impl/loader_io.dart`
  - `lib/src/loader/impl/loader_web.dart`
  - `lib/src/loader/impl/wasm_loader_web.dart`
  - focused IO/Web tests initialization policy
  - native library paths и packaging не менять — это YUV-06

### Проблема

Публичная доксрока обещает idempotent initialization и только `StateError`, но фактические контракты backend различаются:

- IO-загрузка синхронна. Успешный результат кэшируется в `_library`, поэтому последовательные и фактически параллельные успешные вызовы уже не открывают библиотеку повторно.
- После IO-ошибки `_library` остаётся `null`, поэтому следующий вызов повторяет попытку.
- Web делит один `_initFuture`, но сохраняет failed future навсегда; повторная попытка в том же процессе невозможна.
- IO может передать наружу `UnsupportedError` либо исходную ошибку `DynamicLibrary.open`, тогда как Web configuration failures используют `StateError`.
- IO-операции сейчас могут лениво открыть library через getter без предварительного `ensureInitialized()`, хотя публичная документация требует вызвать initialization заранее. На Web предварительный вызов действительно обязателен.

Повтор после ошибки сам по себе не нарушает idempotency. Дефект — незадокументированная и разная retry/error/lazy-init policy.

### Зафиксированное решение

1. Сохранить обратную совместимость IO: `ensureInitialized()` рекомендуется для ранней диагностики, но native getter может лениво открыть library. На Web явная initialization до операций остаётся обязательной. Различие прямо описать в публичной доксроке.
2. Зафиксировать retry-after-failure для обоих backend. Успешная инициализация кэшируется; failed attempt не блокирует следующую явную попытку.
3. На Web параллельные callers делят один in-flight future. При ошибке очищать `_initFuture` только если он всё ещё относится к этой попытке; `_module` после ошибки остаётся `null`.
4. Не добавлять native in-flight future только ради симметрии: текущий IO open синхронный. Если реализация станет асинхронной, тогда применить настоящий single-flight.
5. Не оборачивать все ошибки искусственно в `StateError`. Задокументировать фактические категории: Web configuration/runtime `StateError`, unsupported native platform `UnsupportedError`, ошибка открытия dynamic library — исходная platform/FFI error. Исходные object, message и stack trace должны сохраняться через `rethrow`.
6. Добавить test seams для opener/module initializer, чтобы детерминированно проверить concurrent success, failure и retry без удаления/подмены реальных binaries.
7. Reset seam, если нужен только тестам, не делать публичным. Он очищает согласованно library, bindings, module и in-flight future.
8. Не менять generated bindings и native C.

### DoD

- Повторный успешный IO-вызов не выполняет второй open; concurrent callers также наблюдают один успешный open.
- После IO-ошибки следующая явная попытка реально выполняется и может завершиться успешно.
- Параллельные Web-вызовы делят одну попытку; после failed future следующий вызов создаёт новую попытку.
- Failed Web attempt не оставляет `_module` или иной частично инициализированный state.
- Публичная доксрока точно описывает различия IO lazy init и обязательной Web initialization.
- Тесты подтверждают фактические exception types и сохранение исходного stack trace без проверки хрупкого полного текста platform message.
- Reset test seam не доступен из публичного package API и не оставляет bindings от старой library.
- YUV-06 остаётся единственным владельцем изменений native paths/packaging.

### Проверка

```powershell
flutter test test/loader_io_test.dart --reporter expanded
flutter test --platform chrome test/web/wasm_loader_initialization_test.dart --reporter expanded
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

В результате отдельно записать число фактических opener/initializer invocations для success, concurrent и retry cases. Для Web подтвердить `kIsWeb == true`.

### Результат

Не заполнен.

---

## YUV-18 — финальная приёмка и подготовка `0.2.5`

- Владелец: Terra
- Приоритет: P0 / release gate
- Статус: BLOCKED
- Зависимости: YUV-01…YUV-17, YUV-19…YUV-21
- Scope:
  - интеграционное ревью всех task commits;
  - `pubspec.yaml` и верхняя запись `CHANGELOG.md`;
  - release verification без tag/push;
  - никаких новых feature/refactor изменений.

### Проблема

`0.2.4` уже помечен tag, но имеет Web compile blocker, ложный Web CI, native memory-safety риски, потерю Y в `swapNv()` и неподтверждённые Linux/macOS paths. Отдельные зелёные проверки не доказывают готовность package целиком.

### Зафиксированное решение

1. Независимо пересмотреть каждый task diff и заполненный результат; не принимать самооценку модели без повторного запуска ключевых gates.
2. Проверить, что зависимости выполнены и ни одна C-задача не обошла approval.
3. Убедиться, что `failed-test-cases.md` не содержит unresolved P0/P1 failures и что все resolved entries имеют повторный успешный reference run.
4. Провести clean-checkout matrix:
   - Dart/Flutter analysis;
   - VM/widget tests;
   - настоящий Chrome Web suite;
   - native build/runtime smoke на Windows, Linux, macOS;
   - Android/iOS build checks;
   - publish dry run.
5. Установить `0.2.5` одновременно в `pubspec.yaml` и верхней записи `CHANGELOG.md`.
6. Проверить содержимое publish archive на отсутствие `_tmp_*`, локальных DLL и иных developer artifacts, не читая `build/`.
7. Не создавать tag и не делать push без отдельного запроса владельца.

### DoD

- Все YUV-01…YUV-17 и YUV-19…YUV-21 имеют статус `DONE` и независимое verification evidence.
- Полная reference matrix на `test_pattern_512.png` проходит на native и Web либо имеет явно согласованные ограничения; unresolved P0/P1 failures отсутствуют.
- P0/P1 findings из аудита либо устранены, либо явно сняты владельцем с документированным основанием.
- `flutter analyze` проходит из корня.
- Полный VM suite и реальный Chrome suite проходят.
- Native runtime smoke подтверждён на Windows/Linux/macOS; mobile builds подтверждены.
- `flutter pub publish --dry-run` завершается с 0 warnings.
- `pubspec.yaml` и верхняя версия CHANGELOG равны `0.2.5`.
- Рабочее дерево содержит только ожидаемые release changes.
- Tag/push не выполнялись.

### Проверка

```powershell
flutter analyze
flutter test
flutter test --platform chrome test/web
flutter pub publish --dry-run
git diff --check
git status --short --branch
git diff --stat 0.2.4..HEAD
```

К результату приложить platform-specific build/runtime команды, CI URLs и финальный список файлов publish dry run.

### Результат

Не заполнен.
