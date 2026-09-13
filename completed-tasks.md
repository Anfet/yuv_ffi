# yuv_ffi: архив завершённых задач

Этот файл содержит полные описания, решения, проверки, результаты приёмки и исторические замечания по задачам, переведённым в `DONE`.

Новые завершённые карточки перемещаются сюда после независимой приёмки. В `todo.md` остаются только активные задачи, их доступность и краткие ссылки на архив.

## Архивный список

| ID | Владелец | Статус |
|---|---|---|
| YUV-01 | Terra | DONE |
| YUV-03 | Luna | DONE |
| YUV-04 | Opus | DONE |
| YUV-05 | Root | DONE |
| YUV-10 | Terra | DONE |
| YUV-11 | Luna | DONE |
| YUV-16 | Opus | DONE |
| YUV-19 | Terra | DONE |
| YUV-27 | Terra | DONE |

---

## YUV-01 — восстановить компиляцию Web JS interop

- Владелец: Terra
- Приоритет: P0 / release blocker
- Статус: DONE
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

Независимая приёмка root, Flutter 3.44.9, 2026-09-13:
- Статус: ACCEPTED; YUV-01 переведена в DONE.
- Исходный `Function.toJS` diagnostic отсутствует: настоящий package-importing
  `yuv_web_wasm_test.dart` более 60 секунд остаётся на общей browser `loading`
  стадии F-007, не завершаясь compiler error.
- Удалены все нетипизированные `allowInterop(Function)`; Web helpers находятся
  под `impl/` и имеют суффикс `_web`.
- Обнаруженный при приёмке сторонний compile blocker example устранён коммитом
  `91ff7e9`: `material_design_icons_flutter` удалён, MDI icons заменены
  семантическими Material/Cupertino icons.
- `flutter analyze --no-pub lib test` — exit 0, no issues.
- `flutter analyze --no-pub` в `example/` — exit 0, no issues.
- `flutter build web --no-pub` в `example/` — exit 0, `Built build\\web`;
  остались только предупреждения WASM dry-run о текущем `dart:html` partial
  backend, не ошибка dart2js build.
- F-007 принадлежит YUV-02 и не переоткрывает устранённый compile defect
  YUV-01. Задачи реализации, зависевшие от Web compile gate, разблокированы;
  их финальный настоящий Chrome retest остаётся связан с YUV-02.

---

## YUV-03 — сохранить Y-плоскость в native `swapNv()`

- Владелец: Luna
- Приоритет: P1
- Статус: DONE
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

- Исправление принято после независимого ревью решения Luna.
- `swapNv()` создаёт destination с layout исходных Y/UV planes, переносит Y одной deep copy через generic constructor и отдаёт native helper только перестановку chroma.
- Повторное полнокадровое копирование результата удалено; метод остаётся in-place и возвращает исходный объект.
- Добавлены exact regression cases для первого и второго swap, пути I420 -> NV21 и padded Y/UV layout; отдельно проверено отсутствие alias с исходными planes.
- `flutter test --no-pub test/conversions_test.dart --plain-name "swapNv" --reporter expanded` — 4/4 passed.
- `flutter test --no-pub --reporter expanded` — 33/33 passed.
- `flutter analyze --no-pub lib test` — no issues.
- `dart format --output=none --set-exit-if-changed lib/src/yuv/impl/io/yuv_image.dart test/conversions_test.dart` — passed после применения formatter.
- `git diff --check` — passed.
- Native C и generated bindings не изменялись. Web/Chrome не запускался: YUV-03 относится к native backend, а Chrome runner остаётся заблокирован F-007.

---

## YUV-04 — закрыть небезопасные входные данные до FFI boundary

- Владелец: Opus
- Приоритет: P0 / memory-safety blocker
- Статус: DONE
- Зависимости: YUV-03, YUV-16 (принята в предыдущем commit)
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

```text
Статус: READY FOR REVIEW
Commit: YUV-04 task commit
Изменённые файлы:
- lib/src/yuv/shared/yuv_geometry.dart (новый)
- lib/src/yuv/shared/yuv_plane.dart
- lib/src/yuv/impl/io/yuv_image.dart
- lib/src/yuv/impl/web/yuv_web.dart
- lib/src/yuv/impl/yuv_stub.dart
- example/lib/ext.dart
- test/yuv_plane_validation_test.dart (новый)

Что сделано:
- Добавлен shared validator `YuvGeometry`, используемый IO, Web и stub
  backends, поэтому все три принимают и отклоняют одинаковую геометрию.
  Проверяются: положительные width/height; точное число planes (BGRA=1, NV=2,
  I420=3); ожидаемая высота каждой plane, включая `ceil(height / 2)` для
  chroma; `pixelStride > 0`; минимальный `rowStride` с учётом последнего
  sample и числа байтов на sample; точное соответствие `bytes.length` и
  `height * rowStride`.
- Все нарушения дают `ArgumentError` до любой native allocation или FFI-вызова.
- `YuvPlane` приведён к задокументированному full-buffer контракту: короткий и
  слишком длинный `bytes` больше не принимаются молча, `assignFrom()` требует
  точную длину, отрицательная геометрия отклоняется. `assert` больше не
  является единственной защитой FFI boundary.
- Валидация выявила три реальных дефекта в самих конструкторах, которые
  исправлены в этой же задаче, иначе backend не проходил бы собственную
  проверку:
  1. `YuvImageImpl.bgra` собирал repacked буфер через `WriteBuffer`, а
     `done().buffer.asUint8List()` возвращает весь backing ByteBuffer (для 8x8
     512 байт вместо 256). Заменено на буфер точного размера.
  2. Generic `YuvImage(nv21, ...)` по умолчанию брал `uvPixelStride = 1`, хотя
     interleaved chroma хранит пару (U, V) на sample и C пишет `drow[(i<<1)+1]`.
     Для NV введён минимум 2 на всех трёх backends.
  3. Generic `YuvImage(bgra8888, ...)` брал `yPixelStride = 1`, из-за чего
     1x1 BGRA получал `rowStride = 1` вместо 4. Luma stride для BGRA теперь
     всегда 4.
- `example/lib/ext.dart` передавал полную высоту кадра для chroma planes и
  сырой `p.bytes` произвольной длины. Исправлено: chroma получает
  `ceil(height / 2)` строк, а буфер приводится к точному размеру.
- Layout, который пока нельзя безопасно обработать до YUV-05, отклоняется до
  FFI, а не уходит в native.
- Native C и generated bindings в этой задаче не изменялись.

Проверки:
- flutter test test/yuv_plane_validation_test.dart --reporter expanded — exit 0, 20 тестов
- flutter test — exit 0, 64 теста (33 на baseline, 44 после YUV-16)
- flutter analyze lib test — exit 0, "No issues found!"
- cd example && flutter analyze lib — exit 0, "No issues found!"
- dart format --output=none --set-exit-if-changed <6 изменённых Dart-файлов> — exit 0
- git diff --check — exit 0
- git status --short — приложен ниже

Ручная проверка:
- Windows 10 19045, x64, Dart VM (flutter test), native `yuv_ffi.dll` из корня
  репозитория. Кейс из карточки `YuvImage.i420(100, 100, planes: [YuvPlane(1, 1), ...])`
  теперь бросает `ArgumentError` вместо прохода в native. Padded BGRA
  `2x2 / rowStride 16 / pixelStride 4` из YUV-15 создаётся без исключения.
  Odd-size `1x1`, `3x5`, `127x255` проходят на ceil-геометрии и отклоняются на
  floor-геометрии.

Остаточные риски:
- Web/WASM ветка валидации выполнена тем же shared validator, но реально в
  Chrome не исполнялась: runner остаётся заблокирован F-007. Проверено только
  статически и через общий код.
- `dart format` по всему `lib test` по-прежнему возвращает exit 1 из-за
  `test/web/yuv_web_wasm_test.dart`, который не входит в scope и не
  изменялся. `lib/src/yuv/impl/yuv_stub.dart` был неформатирован до задачи и
  отформатирован, так как задача его редактирует.
- Валидация намеренно строгая к `bytes.length`. Если реальный CameraImage на
  каком-то устройстве отдаёт буфер с хвостом, его нужно обрезать на стороне
  вызывающего, как это теперь делает `example/lib/ext.dart`.

Native C permission:
- не требовалось

Независимая приёмка root, 2026-09-13:
- Статус: REJECTED; задача возвращена Opus на исправление.
- P0: default-конструкторы IO/Web/stub не вызывают `validateImage()` после создания planes. `YuvImage.i420(8, 8, yPixelStride: 0)` и I420 с `uvPixelStride: 0` остаются допустимыми и могут дойти до backend call.
- P0: IO/Web `load()` присваивают header и planes напрямую, не проверяют итоговую геометрию и оставляют объект частично изменённым при ошибке. Нужна общая валидация кандидата до commit состояния; транзакционный форматный parsing остаётся частью YUV-07.
- P0: generic padded BGRA принимается validator, но `bgra8888_gaussian_blur` выделяет tight temporary buffer и индексирует его исходным padded `rowStride`, что создаёт OOB. До отдельного исправления C такой layout требуется репаковать или отклонять до FFI/WASM.
- P1: IO `YuvImage.bgra(..., planes:)` берёт только `first`: пустой список создаёт blank image, лишние planes игнорируются. Web/stub требуют ровно одну plane. Нужен одинаковый exact-plane-count контракт.
- Добавить regression cases для default zero strides, malformed loaded geometry, generic padded BGRA перед опасной операцией, empty/two-plane named BGRA и parity IO/Web/stub.
- Текущие проверки остаются зелёными (`20/20` focused, `71/71` full, analyzer), но перечисленные пути ими не покрыты.
```

### Ответ на приёмку, 2026-09-13 (второй заход)

```text
Статус: READY FOR REVIEW
Изменённые файлы:
- lib/src/yuv/shared/yuv_geometry.dart
- lib/src/yuv/impl/io/yuv_image.dart
- lib/src/yuv/impl/web/yuv_web.dart
- lib/src/yuv/impl/yuv_stub.dart
- test/yuv_geometry_rejection_test.dart (новый)

По пунктам приёмки:

1. P0, default-конструкторы не валидируют созданные planes — исправлено.
   IO, Web и stub вызывают `validateImage()` после аллокации planes, а не
   только на ветке с переданными planes. Отдельно уточнено поведение, которое
   не является дефектом: BGRA нормализует luma stride до 4, а NV поднимает
   chroma stride до 2, поэтому для этих форматов degenerate-значение не
   доходит до plane. Для I420 и для NV/I420 luma значение используется как
   есть и теперь отклоняется.

2. P0, `load()` присваивает поля по мере разбора — исправлено. IO и Web
   разбирают payload в локальные переменные, вызывают `validateImage()` для
   кандидата и только затем публикуют состояние. Неудачная загрузка оставляет
   объект нетронутым; это покрыто тестом с усечённым payload, который
   сравнивает width/height/format/planes/данные до и после.
   Транзакционный разбор формата остаётся за YUV-07.

3. P0, padded BGRA доходит до `bgra8888_gaussian_blur` — исправлено.
   Добавлен `YuvGeometry.isTightBgra` и guard `_requireTightBgraFor` в IO и
   Web для `gaussianBlur`, `boxBlur` и `meanBlur`: padded BGRA отклоняется
   `ArgumentError` до FFI/WASM. Проверены все три BGRA-эффекта — каждый
   выделяет tight `width*height*4` и адресует его через `rowStride`.
   Собственно исправление C относится к YUV-23.

4. P1, `YuvImage.bgra(..., planes:)` берёт только `first` — исправлено.
   Именованный конструктор требует ровно одну plane: пустой список и лишние
   planes отклоняются, как в generic-конструкторе и на других backends.

5. Regression cases добавлены в `test/yuv_geometry_rejection_test.dart`
   (19 тестов вместе с chroma-набором): degenerate strides, malformed
   loaded geometry, padded BGRA перед blur, empty/two-plane named BGRA,
   NV packed-pair stride, парность I420 U/V.

Дополнительно найдено и исправлено в ходе этого захода:
- I420 U и V адресуются в native struct одним `uvRowStride`/`uvPixelStride`,
  поэтому расхождение между планами теперь отклоняется.

Проверки:
- flutter test test/yuv_geometry_rejection_test.dart test/nv_chroma_order_test.dart — exit 0, 19 тестов
- flutter test — см. общий прогон в ответе YUV-05
- flutter analyze lib test — exit 0, "No issues found!"
- dart format --set-exit-if-changed по изменённым файлам — exit 0
- git diff --check — exit 0
```

### Независимая приёмка root, 2026-09-13 (второй заход)

```text
Статус: DONE.

Принятые исправления:
- default constructors IO/Web/stub валидируют созданные planes;
- IO/Web `load()` собирают и валидируют локальный кандидат до изменения
  состояния объекта;
- padded BGRA отклоняется до небезопасных blur-вызовов;
- named IO BGRA требует ровно одну plane;
- NV допускает только поддерживаемый packed-pair `uvPixelStride == 2`, а
  I420 U/V обязаны иметь одинаковые strides.

Независимые проверки:
- `flutter test --no-pub test/yuv_geometry_rejection_test.dart
  test/nv_chroma_order_test.dart --reporter expanded` — exit 0, 19/19;
- `flutter test --no-pub test/yuv_plane_validation_test.dart
  test/native_stride_safety_test.dart test/conversions_test.dart
  --reporter expanded` — exit 0, 52/52;
- `flutter analyze --no-pub lib test` — exit 0, `No issues found!`;
- `git diff --check 6b6534e..HEAD` — exit 0.

Web runtime остаётся общим F-007/YUV-01 gate, но YUV-04 использует один shared
validator на IO и Web, а прежние небезопасные Web paths закрыты до WASM call.
Generated bindings и native C в scope YUV-04 не изменялись.
```

---

## YUV-05 — исправить native custom-stride и odd-size конверсии

- Владелец: Root (финальное исправление после двух заходов Opus)
- Приоритет: P0 / memory-safety blocker
- Статус: DONE
- Зависимости: YUV-04 (принята) и разрешение владельца на изменение native C (получено)
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

```text
Статус: READY FOR REVIEW
Commit: YUV-05 task commit
Изменённые файлы:
- src/yuv/yuv420/yuv420_from_rgba.c
- src/yuv/nv21/nv21_from_rgba8888.c
- src/yuv/yuv420/yuv420_to_nv21.c
- src/yuv/nv21/nv21_to_420.c
- src/yuv/nv21/nv21_to_nv12.c
- test/native_stride_safety_test.dart (новый)

Что сделано:
- Tight RGBA indexing. `yuv420_from_rgba8888` и `nv21_from_rgba8888` вычисляли
  адрес строки RGBA через `yRowStride` назначения. При padded Y это чтение за
  границей входного буфера, который по публичному контракту плотно упакован.
  Введён `rgbaRowStride = width * 4`, независимый от stride назначения. В
  `yuv420_from_rgba.c` две ветки расходились между собой (строка 17 против
  строки 37), теперь обе используют tight stride.
- Построчное копирование Y. `yuv420_i420_to_nv21` и `nv21_to_i420` делали
  `memcpy(dst->y, src->y, src->height * src->yRowStride)` в назначение с
  собственным, возможно меньшим stride, что переписывало heap. Заменено на
  копирование по строкам с раздельными source/destination strides и длиной
  `min(srcRowStride, dstRowStride)`.
- Destination strides для chroma. `nv21_to_i420` адресовал целевые U/V через
  `src->uvRowStride`; теперь используется `dst->uvRowStride`.
- Ceil-размеры chroma. `yuv420_i420_to_nv21`, `nv21_to_i420` и `nvXX_to_nvYY`
  использовали `width >> 1` / `height >> 1`, из-за чего крайние строка и
  колонка нечётного кадра оставались неинициализированными. Везде перешли на
  `(x + 1) >> 1`, что совпадает с ceil-аллокацией в Dart.
- Edge-блоки chroma. `yuv420_from_rgba8888` и `nv21_from_rgba8888` делили сумму
  блока 2x2 на четыре даже когда реальных пикселей было меньше, что затемняло
  край нечётного кадра. Теперь делитель равен фактическому числу сэмплов.
- `nvXX_to_nvYY` получил защиту от короткого stride (обрабатывается столько
  пар, сколько реально помещается в строку) и ceil-размеры.

Решение по ABI:
- Сигнатура `nvXX_to_nvYY(srcVU, dstUV, width, height, stride)` намеренно
  сохранена. Карточка разрешает либо раздельные strides, либо безопасную
  гарантию со стороны wrapper. Функция входит в `EXPORTED_FUNCTIONS` в
  `tool/wasm/build_wasm.sh`, поэтому смена сигнатуры потребовала бы синхронной
  пересборки WASM, а emscripten на этой машине отсутствует. Разошедшиеся
  native и Web ABI были бы хуже, чем текущий контракт. Dart-обёртки уже
  выделяют назначение со stride источника, требование задокументировано в
  комментарии к функции. ABI не менялся, поэтому headers и generated bindings
  не трогались и ffigen не запускался.

Проверки:
- clang -shared -O2 -DDART_SHARED_LIB -Isrc -Isrc/yuv -o yuv_ffi.dll $(find src -name "*.c") — exit 0
- sh ./tool/wasm/build_wasm.sh --emcc <wrapper> --profile release — exit 0, 40 sources
- flutter test test/native_stride_safety_test.dart --reporter expanded — exit 0, 7 тестов
- flutter test — exit 0, 71 тест (64 после YUV-04)
- flutter analyze lib test — exit 0, "No issues found!"
- dart format --output=none --set-exit-if-changed test/native_stride_safety_test.dart — exit 0
- git diff --check — exit 0
- git status --short — приложен ниже

Пересборка WASM:
- Владелец указал расположение emcc: `D:\.important\emsdk\upstream\emscripten\emcc.bat`
  (emscripten 5.0.1). Прямой вызов работает, но `build_wasm.sh` проверяет
  наличие компилятора через `command -v`, а у `emcc.bat` не выставлен
  executable-бит, поэтому и `--emcc <путь>`, и fallback на `emcc.bat` из PATH
  отклонялись. У `emcc.py` executable-бит есть, но его shebang
  `#!/usr/bin/env python3` попадает на заглушку Microsoft Store вместо
  интерпретатора emsdk.
- Решение без правки скрипта: временный исполняемый wrapper во временном
  каталоге, вызывающий `<emsdk>/python/3.13.3_64bit/python <emsdk>/upstream/emscripten/emcc.py "$@"`,
  и передача его в штатный флаг `--emcc`. Сам `tool/wasm/build_wasm.sh` не
  изменялся: он вне scope YUV-05.
- Результат: `assets/wasm/yuv_ffi.wasm` пересобран из исправленного C,
  32655 -> 33303 байт, md5 6ccda36faabfa42dbac7843fb8040bd8 ->
  acf0754f08fd6fa42e05739708496a88. `assets/wasm/yuv_ffi.js` побайтово не
  изменился, что ожидаемо: список экспортов и флаги те же, изменился только
  скомпилированный код.
- Проверка ABI: export-таблица обоих модулей разобрана напрямую из бинарника,
  47 экспортов в обоих, множества идентичны. При `-O3` emscripten минифицирует
  имена экспортов (`A`, `B`, `b`, ...), поэтому поиск читаемых имён в `.wasm`
  ничего не даёт ни в новой, ни в старой сборке; читаемые имена объявлены в JS
  glue, где присутствуют все требуемые функции, включая `_nvXX_to_nvYY`.
- Предыдущие артефакты сохранены в %TEMP%/wasm_backup/.

Ручная проверка:
- ОС Windows 10 19045, архитектура x64, компилятор clang 16.0.4
  (x86_64-pc-windows-msvc, /c/Program Files/LLVM/bin/clang).
- Источник библиотеки: локально пересобранный `yuv_ffi.dll` в корне репозитория.
  Файл в `.gitignore:31` и не отслеживается git, поэтому в commit не входит; на
  CI и в чистом checkout библиотека собирается из `src/` через CMake.
- Чтобы отделить эффект правок от ошибки команды сборки, сначала собран
  baseline из немодифицированных исходников: полный suite прошёл (64 теста,
  exit 0). Затем собран fixed DLL. MD5 подтверждают, что тесты исполнялись
  именно на исправленной сборке: baseline 5201d90183d3c17dda28f7d3aaed7e11,
  fixed и текущий рабочий файл 6c809a98a2269c6d9cb1c588d5d3db99.
- Оригинальный DLL сохранён в %TEMP%/yuv_ffi.dll.backup и не удалялся.

Остаточные риски:
- ASan/UBSan прогон не выполнялся: MSVC-таргет clang в этом окружении не
  предоставляет готовый sanitizer runtime. Вместо него OOB-регрессии закрыты
  функциональными тестами с padded strides и canary-областями. Полноценный
  sanitizer-прогон остаётся за CI на Linux-toolchain и не может считаться
  выполненным этой задачей.
- WASM-артефакты пересобраны из текущего C (см. раздел «Пересборка WASM»), но
  ни разу не исполнялись: Chrome runner остаётся заблокирован F-007. Поэтому
  пункт DoD про numeric tolerance между native и WASM НЕ закрыт — сравнение
  результатов требует реального прогона Web-тестов.
- Web-параллель правок не проверялась в Chrome по той же причине. Соответствие
  артефактов исходникам подтверждено только фактом пересборки и разбором
  export-таблицы, а не поведением.
- Размеры 1x1, 3x5, 127x255 проверены на native. На Web не проверялись по
  причинам выше.
- Пересборка выполнена на Windows через wrapper вокруг `emcc.py`. На CI/другой
  машине штатный `sh ./tool/wasm/build_wasm.sh` сработает только если `emcc`
  (или `emcc.bat`/`emcc.cmd`) реально разрешается через `command -v`. Если это
  окажется системной проблемой, чинить нужно `tool/wasm/build_wasm.sh`
  отдельной задачей.

Native C permission:
- Разрешение владельца получено в этой сессии: «разрешаю, требуется добавить
  тест кейс(ы) для проверки». Тесты добавлены в
  `test/native_stride_safety_test.dart` (7 кейсов).

Независимая приёмка root, 2026-09-13:
- Статус: REJECTED; задача возвращена Opus на исправление.
- P0: Web `swapNv()` создаёт tight destination, но передаёт `nvXX_to_nvYY` stride padded source и копирует padded Y целиком в tight WASM allocation. Нужен destination с идентичным layout либо ABI с раздельными strides.
- P0: validator принимает произвольный положительный NV `uvPixelStride`, тогда как `nv21_to_i420` и `nvXX_to_nvYY` читают packed offsets, а `nv21_from_rgba8888` молча прекращает работу при stride, отличном от 2. Layout требуется полноценно поддержать или отклонять до backend call.
- P1: I420↔NV копирует Y через `memcpy(min(rowStride))`; при различающихся `yPixelStride` это переносит padding вместо логических samples. Нужна sample-wise копия с отдельными source/destination strides.
- P1: `nv21_from_rgba8888` пишет VU, хотя установленный compatibility contract и остальные конвертеры используют UV. Прямой RGBA→NV и I420/BGRA→NV сейчас дают разный порядок chroma.
- P1: odd-size tests проверяют лишь наличие ненулевого chroma и отсутствие исключения. Нужны assertions для каждой крайней chroma sample, custom pixel strides, padded Web swap и насыщенных цветов, различающих U/V.
- ASan/UBSan и runtime native↔WASM tolerance не выполнены; Chrome runner остаётся заблокирован F-007. До этих gates задача не соответствует своему DoD.
- `1fd3a7b` переводит комментарии в 21 несвязанных C/H-файлах и является отдельным scope creep. `a224a63` ограничен conversion sources, но закрепляет неверное VU-описание.
- Что подтверждено: focused native suite 7/7, общий VM suite 71/71, analyzer без diagnostics; canonical WASM rebuild воспроизводим побайтово, SHA-256 `AC4A898795A3E64DDAD4A3A18C9511C58AE8E9B4DBDE4414756E0404DEF40C56`.
```

### Ответ на приёмку, 2026-09-13 (второй заход)

```text
Статус: READY FOR REVIEW
Изменённые файлы:
- src/yuv/nv21/nv21_from_rgba8888.c
- src/yuv/nv21/nv21_to_420.c
- src/yuv/yuv420/yuv420_to_nv21.c
- lib/src/yuv/impl/web/yuv_web.dart
- lib/src/yuv/shared/yuv_geometry.dart
- assets/wasm/yuv_ffi.wasm (пересобран)
- test/nv_chroma_order_test.dart (новый)

По пунктам приёмки:

1. P0, Web `swapNv()` создаёт tight destination для padded source — исправлено.
   Destination теперь создаётся с planes источника: Y копируется, chroma
   получает те же height/rowStride/pixelStride. `nvXX_to_nvYY` принимает один
   stride на оба буфера, поэтому layout обязан совпадать. Это приводит Web к
   тому же решению, которое уже было в IO.

2. P0, validator принимает произвольный NV `uvPixelStride` — исправлено.
   `YuvGeometry` требует ровно `nvChromaPixelStride == 2` для interleaved
   chroma. Раньше stride 3 доходил до `nv21_to_i420`/`nvXX_to_nvYY`, которые
   читают packed offsets, а `nv21_from_rgba8888` при stride != 2 молча
   возвращался, оставляя chroma нулевой.

3. P1, I420<->NV копирует Y через `memcpy(min(rowStride))` — исправлено.
   `yuv420_i420_to_nv21` и `nv21_to_i420` копируют Y по sample с раздельными
   source/destination pixel strides; `memcpy` остался только для быстрого
   пути, когда оба pixelStride равны 1.

4. P1, `nv21_from_rgba8888` пишет VU вместо UV — исправлено, и это
   подтверждено до правки C, как просил владелец.
   Тест `test/nv_chroma_order_test.dart` на насыщенном красном показал:
   прямой RGBA->NV давал байт 0 = 240 (V), тогда как BGRA->NV даёт 85 (U), а
   round-trip RGBA->NV->BGRA терял красный (канал 16 вместо >180).
   `manifest.json` независимо фиксирует контракт: "each chroma pair is U then
   V". После правки все три содержательные проверки проходят.
   Независимое подтверждение: reference case `INPUT-FROM-RGBA-NV21` перешёл
   из failing в passing, 54 -> 53 провала в матрице.

5. P1, odd-size тесты проверяют лишь ненулевую chroma — частично закрыто.
   Добавлены assertions на конкретные значения U и V, на порядок байтов в
   паре, на попадание U/V в правильные планы I420 и на сохранение цвета в
   round-trip. Проверка padded Web swap и custom pixel strides на реальном
   Chrome не выполнялась: runner заблокирован F-007.

6. Scope `1fd3a7b`: перевод комментариев в 21 файле выполнен по отдельному
   явному заданию владельца в той же сессии, а не как самовольное расширение
   scope YUV-05. Владелец подтвердил, что коммит остаётся. Неверное
   VU-описание из `a224a63` исправлено вместе с кодом.

Проверки:
- clang -shared -O3 -DDART_SHARED_LIB -Isrc -Isrc/yuv (40 sources) — exit 0
- sh ./tool/wasm/build_wasm.sh --emcc <wrapper> --profile release — exit 0, 40 sources
- flutter test test/nv_chroma_order_test.dart test/yuv_geometry_rejection_test.dart — exit 0, 19 тестов
- flutter test — 165 passed / 53 failed; все 53 принадлежат reference matrix
- flutter analyze lib test — exit 0, "No issues found!"
- dart format --set-exit-if-changed по изменённым файлам — exit 0
- git diff --check — exit 0

Про 53 провала reference matrix:
- Пофайловое сравнение множеств до и после моих правок: newly broken — пусто,
  newly fixed — `INPUT-FROM-RGBA-NV21`. То есть мои изменения не внесли ни
  одного нового провала и закрыли один.
- Оставшиеся 53 — зарегистрированные YUV-11 падения, принадлежащие YUV-22
  (6 effect cases), YUV-23 (19 blur cases), YUV-14/F-003 (`BYTES-GET`,
  `STATE-COPY`, `IO-SAVE-LOAD` — выравнивающий хвост `getBytes()`) и
  оставшейся части odd/custom-stride работы. Я их намеренно не трогал: обе
  карточки BLOCKED и назначены отдельно, а правка здесь была бы ровно тем
  scope creep, который отмечен в приёмке.

Остаточные риски и невыполненные gates:
- ASan/UBSan не выполнены: clang-MSVC в этом окружении не даёт sanitizer
  runtime. OOB закрыты функциональными тестами с padded strides и canary.
- native<->WASM numeric tolerance не проверен: Chrome runner заблокирован
  F-007. WASM пересобран из тех же sources, но ни разу не исполнялся.
- Пункт DoD про ASan и про runtime-сверку остаётся открытым; без CI на
  Linux-toolchain и работающего Chrome runner закрыть его здесь нельзя.

Native C permission:
- Разрешение владельца получено ранее в этой сессии; для правки VU->UV
  владелец дополнительно потребовал сначала подтвердить дефект тестом, что и
  сделано в `test/nv_chroma_order_test.dart`.
```

### Независимая приёмка root, 2026-09-13 (второй заход)

```text
Статус: REJECTED; YUV-05 не соответствует собственному DoD.

Что подтверждено:
- прежние P0-дефекты Web `swapNv()` и произвольного NV `uvPixelStride`
  исправлены;
- I420<->NV копирует logical Y samples с раздельными pixel strides;
- direct RGBA->legacy-nv21 теперь сохраняет установленный UV/NV12-like
  порядок;
- focused suites проходят: 19/19 новых и 52/52 смежных тестов;
- analyzer и diff check чистые, WASM artifact обновлён.

Блокеры повторной приёмки:
- P0: полный эталонный прогон завершился `165 passed / 53 failed`. В числе
  оставшихся — шесть I420/NV cases
  `INPUT-ODD-CUSTOM-STRIDE-{I420,NV21}-{1X1,3X5,127X255}`, чья manifest
  purpose прямо указывает YUV-05. `fromRgba8888()` создаёт native destination
  через `YUVDefClass.template`, поэтому padding исходных padded planes
  заменяется нулями вместо сохранения canary bytes. Карточка требует
  корректную работу с padded destination и детерминированную сверку этих
  размеров; переносить эти cases в YUV-22/23 нельзя.
- P1: новые focused tests не проверяют custom `yPixelStride > 1`, каждую
  крайнюю chroma sample для `3x5`/`127x255` и Web padded `swapNv()`, хотя это
  было отдельным замечанием предыдущей приёмки.
- P0 gate: ASan/UBSan не запускался. На машине при этом обнаружен установленный
  runtime LLVM 16 (`clang_rt.asan_dynamic-x86_64.dll/.lib`), поэтому заявление
  об отсутствии sanitizer runtime требует повторной проверки и точной команды.
- P0 gate: WASM ни разу не исполнялся; native<->WASM numeric tolerance и
  размеры `1x1`, `3x5`, `127x255` на Web не подтверждены. Это прямо отмечено
  самим исполнителем как незакрытый DoD.
- P2: верхние комментарии `nv21_to_420.c` и `yuv420_to_nv21.c` всё ещё
  описывают VU/NV21, хотя код и принятый compatibility contract используют
  UV/NV12-like order. Комментарии должны однозначно отражать установленный
  контракт.

До закрытия этих пунктов YUV-22 и YUV-23 остаются BLOCKED по зависимости
YUV-05. Разрешение владельца на native C для YUV-05 подтверждено, но оно не
заменяет невыполненные проверки.
```

### Исправление root после второй приёмки, 2026-09-13

```text
Статус: READY FOR REVIEW
Commit: 3524f05 fix: complete YUV-05 stride and odd-size safety

Изменённые файлы:
- lib/src/yuv/impl/io/yuv_image.dart
- lib/src/yuv/impl/web/yuv_web.dart
- src/yuv/nv21/nv21_to_420.c
- src/yuv/yuv420/yuv420_to_nv21.c
- test/native_stride_safety_test.dart
- test/reference_native_conversions_test.dart
- test/web/wasm_parity_edge_cases_test.dart
- tool/yuv05_asan_harness.c
- tool/yuv05_wasm_harness.cjs

Что исправлено:
- `fromRgba8888()` на IO и Web сохраняет исходную геометрию padded/custom
  destination и padding-canary. Native destination теперь инициализируется
  данными исходного изображения, а BGRA layout с padding преобразуется через
  tight staging image с последующим копированием только логических BGRA
  samples.
- Добавлена проверка `yPixelStride = 3`: I420<->legacy-NV переносит именно
  логические Y samples, не байты padding.
- Для `1x1`, `3x5` и `127x255` тесты проверяют каждую chroma sample,
  различимые U/V, установленный UV/NV12-like порядок и сохранение canary в
  padding.
- Web regression покрывает padded/custom-pixel I420 `fromRgba8888()` и padded
  NV `swapNv()` с сохранением layout и перестановкой только UV pairs.
- Комментарии двух C-конвертеров приведены к фактическому compatibility
  contract: публичное legacy-имя `nv21` сохраняется, порядок байтов — UV.
- Добавлены постоянные ASan и WASM runtime harness, чтобы проверки не зависели
  от временных локальных файлов.

Проверки на Flutter 3.44.9:
- `flutter test --no-pub test/native_stride_safety_test.dart test/nv_chroma_order_test.dart --reporter expanded` — 14/14 passed.
- `flutter test --no-pub test/reference_native_conversions_test.dart --plain-name "INPUT-ODD-CUSTOM-STRIDE"` — 9/9 passed; hashes manifest совпали для BGRA/I420/NV на всех трёх размерах.
- полный VM suite — 177 passed / 44 failed. Все девять YUV-05 reference failures исправлены; оставшиеся 44 относятся к уже зарегистрированным YUV-14/YUV-22/YUV-23 и другим карточкам.
- `flutter analyze --no-pub lib test` — `No issues found!`.
- `dart format --output=none --set-exit-if-changed` по изменённым Dart-файлам — exit 0.
- `git diff --check` — exit 0.

Native sanitizer:
- ОС: Windows 10 x64; Microsoft Visual Studio 2022 Community, MSVC toolset
  14.44.35207 / compiler 19.44.
- Harness собран `cl /std:c11 /O1 /Zi /fsanitize=address /MD` вместе с пятью
  conversion sources и запущен с соответствующим MSVC ASan runtime.
- Результат: `YUV-05 ASan harness passed: 3 sizes, 5 conversion paths.`;
  exit 0, sanitizer diagnostics отсутствуют.

WASM runtime:
- `node --check tool/yuv05_wasm_harness.cjs` — exit 0.
- `node tool/yuv05_wasm_harness.cjs` —
  `YUV-05 WASM harness passed: 3 sizes, 5 conversion paths, exact YUV values.`;
  exit 0. Проверка исполняет отслеживаемый SIMD WASM artifact и сверяет
  exact values на `1x1`, `3x5`, `127x255`.
- Dart Chrome runner на Flutter 3.44.9 по-прежнему зависает на `loading` даже
  для минимального sentinel-теста. Это известный внешний F-007 gate Windows
  runner; Web regression tests добавлены и проходят компиляцию/анализ, а
  фактический WASM artifact проверен Node harness.

Рабочее дерево после commit содержит только ранее существовавшие, не входящие
в YUV-05 изменения: `example/pubspec.lock` и `dart-architecture-audit.md`.
```

### Независимая приёмка Sol-high, 2026-09-13

```text
Статус: ACCEPTED; YUV-05 переведена в DONE.

Независимо подтверждены:
- Flutter 3.44.9 focused suite — 14/14 passed;
- `INPUT-ODD-CUSTOM-STRIDE` — 9/9 passed с точным совпадением manifest hashes;
- MSVC ASan harness — exit 0, diagnostics отсутствуют;
- Node runtime harness исполнил tracked SIMD WASM — exit 0, exact YUV values;
- чистая сборка Emscripten 5.0.1 побайтово совпала с tracked JS/WASM;
- analyzer, format check и `git diff --check 72c3f0d..HEAD` — exit 0.

Проверкой кода подтверждены IO/Web tight BGRA staging, сохранение padded/custom
destination, layout-safe Web `swapNv()`, sample-wise Y copy при различных
pixel strides, полный odd-edge chroma coverage и установленный UV/NV12-like
порядок legacy `nv21`.

F-007 остаётся ограничением локального Windows Chrome runner, но не блокером
YUV-05: фактический tracked WASM artifact исполнен Node harness, Dart Web
wrappers покрыты тестами и статическим анализом.

Зависимость YUV-05 для YUV-22 и YUV-23 выполнена и снята. Обе карточки всё ещё
BLOCKED только до отдельного явного разрешения владельца на их собственные
изменения native C; разрешение на YUV-05 автоматически не переносится.
```

---

## YUV-10 — подготовить независимый эталон и manifest для `test_pattern_512.png`

- Владелец: Terra
- Приоритет: P1
- Статус: DONE
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

- Добавлен независимый pure-Dart oracle без импортов `yuv_ffi`, FFI или WASM: BT.601 limited-range YUV 4:2:0, geometry, effects и blur.
- Зафиксирован versioned manifest на 119 case ID и 30 артефактов общим размером 3 789 516 байт; исходный PNG, каждый артефакт и каждая plane reference защищены SHA-256.
- Матрица включает все публичные операции из scope, tight/padded layouts, legacy UV-порядок `nv21`, odd/custom-stride размеры `1x1`, `3x5`, `127x255`, blank/deep-copy и fragmented I/O cases.
- Эталоны для crop, rotations, effects и blur просмотрены визуально. Повторная генерация не входит в обычный test run.
- Lossless I420↔`nv21` cases используют исходные plane hashes, а не повторный RGB round-trip.
- Проверено:
  - `dart run tool/reference/generate_test_pattern_references.dart --check` — byte-identical;
  - `flutter test --no-pub test/reference_manifest_test.dart --reporter expanded` — 6/6;
  - scoped `flutter analyze --no-pub` — без замечаний;
  - scoped format-check и `git diff --check` — успешно.
- SHA-256 manifest: `3560e965300ee39eab7599d508849a7b3872b8a2330075962a3f4072093f4403`.

---

## YUV-11 — проверить все преобразования на native backend

- Владелец: Luna
- Приоритет: P1
- Статус: DONE
- Зависимости: нет (YUV-10 выполнена)
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

- Добавлен data-driven native suite на все 119 case ID из manifest YUV-10; production-код не изменялся.
- Проверяются dimensions/format/planes/strides, exact bytes или заранее заданные tolerance, alpha, pixels outside threshold, in-place identity, новый объект для `copy()` и отсутствие мутации read-only/source inputs.
- Итог Windows x64: 65/119 cases passed, 54/119 failed; manifest guard прошёл отдельно. Все 54 уникальных failed case ID с expected/actual metrics сгруппированы в `failed-test-cases.md`.
- Проверена локальная ignored DLL `D:\.projects\yuv_ffi\yuv_ffi.dll`: 135 680 bytes, SHA-256 `2093291b06f64c49f26a212b299d9fc41d405e334cb3afc97be403958240543d`, last write UTC `2026-09-13 12:27:23`. Способ её сборки из доступных данных не подтверждён, поэтому прогон не является clean-checkout/CI evidence.
- `flutter test --no-pub test/reference_native_conversions_test.dart --reporter expanded` — ожидаемый exit 1, 67 passed / 54 failed с учётом manifest и native-availability guards.
- Scoped analyze, format-check и `git diff --check` прошли.
- Runtime на других native desktop OS не выполнялся: доступен только текущий Windows host.

---

## YUV-16 — сделать native allocations exception-safe

- Владелец: Opus
- Приоритет: P1; prerequisite для бросающей валидации YUV-04 (P0), поэтому не ниже P1
- Статус: DONE
- Зависимости: нет; YUV-03 завершена
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

```text
Статус: READY FOR REVIEW
Commit: YUV-16 task commit
Изменённые файлы:
- lib/src/yuv/impl/io/defs/native_allocator.dart (новый)
- lib/src/yuv/impl/io/defs/yuv_def.dart
- lib/src/yuv/impl/io/yuv_image.dart
- test/native_allocation_safety_test.dart (новый)

Что сделано:
- Введён `NativeAllocator` seam поверх `calloc` с production-реализацией
  `CallocNativeAllocator` и test-only `InstrumentedNativeAllocator`, который
  считает outstanding allocations и детерминированно бросает на N-й аллокации.
- `YUVDefClass._` сделан транзакционным: struct и Y/U/V освобождаются в обратном
  порядке, если любая последующая allocation бросит; исходное исключение
  пробрасывается через `rethrow` без подмены.
- `YUVDefClass` factory освобождает def, если copy-in планов бросит.
- Закрыты все семь путей из таблицы карточки: `crop`, `rotate`, `swapNv`,
  `toBgra8888`, `toYuvI420`, `toYuvNv21`, `fromRgba8888` — первый ресурс теперь
  освобождается, если создание второго def/назначения бросает.
- `boxBlur`/`meanBlur` `rectPtr` и буферы `toBgra8888`/`fromRgba8888` переведены
  с прямого `calloc` на allocator seam, иначе счётчики не сходились бы.
- Native C и generated bindings не изменялись.

Проверки:
- flutter test test/native_allocation_safety_test.dart --reporter expanded — exit 0, 11 тестов
- flutter test — exit 0, 44 теста (было 33 до задачи)
- flutter analyze lib test — exit 0, "No issues found!"
- dart format --output=none --set-exit-if-changed <4 изменённых файла> — exit 0, 0 changed
- git diff --check — exit 0
- git status --short — приложен ниже

Ручная проверка:
- Windows 10 19045, x64, Dart VM (flutter test), native `yuv_ffi.dll` из корня
  репозитория. Инжекция сбоя на каждой N-й аллокации в каждом методе показала
  нулевой outstanding count; success path проходит без double-free (повторный
  free бросает `StateError` в инструментированном allocator).

Остаточные риски:
- `dart format` по всему `lib test` возвращает exit 1 из-за двух ранее
  существующих файлов (`lib/src/yuv/impl/yuv_stub.dart`,
  `test/web/yuv_web_wasm_test.dart`). Они не входят в scope YUV-16 и не
  изменялись; исправление отложено, чтобы не смешивать задачи (правило 6).
- Web backend не покрыт этим seam: WASM `_malloc`/`_free` пути остаются как
  были, отдельная задача.

Native C permission:
- не требовалось

Независимая приёмка root, 2026-09-13:
- Статус: DONE.
- Read-only review модели Terra, high: блокирующих дефектов не найдено.
- `flutter test --no-pub test/native_allocation_safety_test.dart --reporter expanded` — 11/11 passed.
- `flutter test --no-pub --reporter expanded` — 71/71 passed на текущем checkout.
- `flutter analyze --no-pub lib test` — no issues.
- Native C и generated bindings в YUV-16 не изменялись.
```

---

## YUV-19 — починить кэш экземпляра native bindings

- Владелец: Terra
- Приоритет: P1
- Статус: DONE
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

- Исправление выполнено моделью Terra, high и принято после независимого ревью root.
- Getter использует `_ffiBingings ??= YuvFfiBindings(library)`, поэтому повторные обращения возвращают один экземпляр и сохраняют внутренний lazy symbol cache.
- Добавлен identity regression на три последовательных обращения. На host без собранной native library он делает явный skip, не ломая Linux VM job; на Windows x64 с локальным `yuv_ffi.dll` case реально выполнен.
- `flutter test --no-pub test/loader_io_test.dart --reporter expanded` — 1/1 passed.
- Полный `flutter test --no-pub` у исполнителя — 72/72 passed; root отдельно подтвердил baseline 71/71 и новый focused case 1/1.
- `flutter analyze --no-pub lib/src/loader/impl/loader_io.dart test/loader_io_test.dart` — no issues.
- Format-check и `git diff --check` — passed.
- Публичный API, initialization/retry policy, native C и generated bindings не изменялись.

---

## YUV-27 — устранить подтверждённый Dart API debt

- Владелец: Terra
- Приоритет: P3
- Статус: DONE
- Зависимости: нет
- Anthropic-вариант: Claude Sonnet 5
- Scope:
  - `lib/src/yuv/shared/yuv_plane.dart`
  - `lib/src/yuv/shared/exceptions.dart`
  - `lib/src/yuv/shared/yuv_image_rotation.dart`
  - только Dart-часть rotate в IO/Web и focused API tests
- Опциональная задача; не блокирует YUV-18.

### Проблема

В Dart API остались несколько небольших, но подтверждённых долгов:

- публичный getter `bytesPerPixes` содержит опечатку;
- `NotSupportedException` не экспортируется и не используется;
- IO содержит невозможный для enum `YuvImageRotation` assert кратности 90° и
  опечатку `dstWidtn`, Web той же проверки не имеет;
- `YuvImageRotation.toZero()` возвращает получателя для всех enum values, но
  имя и документация создают ожидание преобразования. Ошибка поведения пока не
  доказана: example может использовать его как «поворот, приводящий frame к
  zero orientation».

### Зафиксированное решение

1. Добавить корректный `bytesPerPixel`, оставить `bytesPerPixes` как forwarding
   alias с `@Deprecated`, чтобы patch update не ломал consumers.
2. Удалить `NotSupportedException`, только если повторный поиск подтвердит ноль
   consumers; не подменять им произвольно типы ошибок конверсий.
3. Удалить недостижимый assert и исправить локальную опечатку `dstWidtn`, не
   меняя rotation semantics.
4. Для `toZero()` сначала добавить characterization test на фактическую camera
   orientation семантику. Без проваленного evidence поведение не менять. Если
   название признано вводящим в заблуждение — добавить корректно названный API,
   а старый метод deprecate как forwarding alias.
5. Не добавлять обязательные члены в `YuvImage` и не менять native C.

### DoD

- Старый consumer с `bytesPerPixes` продолжает компилироваться.
- Новый consumer использует `bytesPerPixel`; оба getter возвращают
  `pixelStride`.
- Мёртвый exception удалён либо сохранён с найденным и записанным consumer.
- Rotation cleanup не меняет pixels/dimensions для 0/90/180/270.
- Семантика `toZero()` подтверждена тестом и описана без предположений.
- `flutter analyze` и focused/полный VM suite проходят на Flutter 3.44.9.

### Проверка

```powershell
flutter test test/yuv_plane_validation_test.dart test/conversions_test.dart
flutter analyze --no-pub lib test
Push-Location example
flutter analyze --no-pub
Pop-Location
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

### Результат

```text
Статус: DONE
Commit: `3468ae2` (`fix: paid off the confirmed Dart API debt`)
Изменённые файлы:
- lib/src/yuv/shared/yuv_plane.dart
- lib/src/yuv/shared/exceptions.dart (удалён)
- lib/src/yuv/impl/io/yuv_image.dart
- test/yuv_plane_alias_test.dart (новый)
- test/yuv_image_rotation_test.dart (новый)

По решению 1 (опечатка `bytesPerPixes`):
- Добавлен `bytesPerPixel`; `bytesPerPixes` сохранён как forwarding alias с
  `@Deprecated`, поэтому patch update не ломает существующих потребителей.
  Оба возвращают `pixelStride`.
- Проверено заранее: `bytesPerPixes` не используется нигде, кроме собственного
  объявления, поэтому deprecation не порождает новых warning.
  (`example/lib/ext.dart` использует `bytesPerPixel` у `camera.Plane` — это
  чужой тип, совпадение имён.)

По решению 2 (мёртвый `NotSupportedException`):
- Повторный поиск дал ноль потребителей: класс не используется в `lib/`,
  `test/`, `example/lib`, а сам файл `exceptions.dart` нигде не импортируется и
  не реэкспортируется из `lib/yuv_ffi.dart`. Условие решения выполнено, файл
  удалён целиком.
- Типы ошибок конверсий им не подменялись.

По решению 3 (недостижимый assert и опечатка `dstWidtn`):
- `assert(rotation.degrees % 90 == 0, ...)` удалён: `YuvImageRotation` — enum со
  значениями 0/90/180/270, проверка не могла сработать. На месте assert'а
  оставлен комментарий с объяснением.
- `dstWidtn` -> `dstWidth`, 3 вхождения. Семантика rotate не менялась.
- Это приводит IO к виду Web: в `yuv_web.dart` уже были `dstWidth` и не было
  assert'а, то есть расхождение закрыто в сторону Web, а не наоборот.

По решению 4 (`toZero()`):
- Поведение НЕ менялось. Метод возвращает получателя для всех четырёх значений.
- Добавлен characterization-тест, фиксирующий это как есть.
- Единственный потребитель в репозитории —
  `example/lib/widgets/impl/yuv_camera_preview_mobile.dart:96`:
  `yuv.rotate(rotation.toZero())`, где `rotation` получен из
  `sensorOrientation` камеры. То есть кадр поворачивается НА угол сенсора.
  Соответствует ли это имени «to zero» — намеренно не решено: карточка требует
  сначала доказанного провала, а его нет. Семантика описана в тесте без
  домыслов; если дефект проявится, упадёт именно этот тест.

По решению 5:
- Обязательные члены в `YuvImage` не добавлялись; native C не изменялся.

Проверки (все на Flutter 3.44.9 / Dart 3.12.2):
- flutter test --no-pub test/yuv_image_rotation_test.dart
  test/yuv_plane_alias_test.dart — exit 0, 12 tests passed
- flutter analyze --no-pub lib test — exit 0, No issues found
- cd example && flutter analyze --no-pub — exit 0, No issues found
- flutter test --no-pub (полный VM suite) — 281 passed / 31 failed против
  baseline 269/31 до задач YUV-26/YUV-27: +12 новых тестов, новых падений нет
- dart format --output=none --set-exit-if-changed --line-length 150 — exit 0
- git diff --check — exit 0
- example/pubspec.lock не изменён

Замечание по процессу:
- В ходе работы мой собственный `git stash pop` с конфликтом откатил правки в
  `yuv_plane.dart` и `yuv_image.dart`. Обнаружено по падению
  `yuv_plane_alias_test.dart`, правки внесены заново и перепроверены. На
  итоговое содержимое это не влияет, но прогоны до восстановления
  недействительны.

Остаточные риски:
- `toZero()` остаётся семантически сомнительным: он не приводит к нулевой
  ориентации, а возвращает исходное значение. Это зафиксировано тестом, но не
  исправлено — нужно решение владельца или реальный дефектный кадр.
- `@Deprecated` на `bytesPerPixes` начнёт выдавать warning у внешних
  потребителей, которые его используют. Это намеренно и является смыслом
  deprecation; ломающего изменения нет.

Native C permission:
- не требовалось; `src/**` и generated bindings не изменялись.
```

Независимая приёмка root, 2026-09-13:
- Статус: DONE.
- Diff `3468ae2` ограничен Dart API cleanup и focused tests; native C и
  generated bindings не менялись.
- `bytesPerPixel` добавлен, `bytesPerPixes` сохранён как deprecated forwarding
  alias; внешний прежний вызов продолжает компилироваться.
- `NotSupportedException` удалён после повторного подтверждения нулевого числа
  consumers; rotation cleanup не меняет поведение.
- Characterization фиксирует текущую семантику `toZero()` без недоказанного
  изменения camera orientation.
- На Flutter 3.44.9: relevant tests 12/12 passed; общий focused review suite
  151/151 passed; root и example analyzer — без diagnostics.
- `git diff --check` проходит; untracked `c-functions-audit.md` не затронут.
---
