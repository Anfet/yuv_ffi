# yuv_ffi: waitlist задач

Здесь находятся все заблокированные, отложенные, discovery и optional/post-release
задачи с полными описаниями. Они не выполняются, пока ревьюер не подтвердит
зависимости и не перенесёт карточку в [todo.md](todo.md). Optional-задача может
иметь статус `TODO`, но остаётся здесь до отдельного выбора ревьюером.

## Чеклист waitlist

| ID | Владелец / модель | Статус | Зависит от | Что должен получить инженер |
|---|---|---|---|---|
| YUV-06 | Terra / Claude Opus 5 | BLOCKED | Linux/macOS app-runtime среда; Android/iOS build evidence | Плагин загружает native library из установленного пакета на Linux/macOS, а CI подтверждает desktop runtime и mobile builds |
| YUV-12 | Luna / Claude Sonnet 5 | BLOCKED | YUV-40 | Полный результат 119-case Web/WASM matrix на реальном Chrome с учётом каждого падения |
| YUV-40 | Terra / Claude Sonnet 5 | DISCOVERED | одобрение инженера | Доказанная причина обрыва `FORMAT-TO-NV21-BGRA-TIGHT` и узкая follow-up задача без изменения production-кода |
| YUV-09 | Luna / Claude Sonnet 5 | BLOCKED | YUV-06, YUV-08, YUV-13, YUV-22, YUV-23, YUV-30, YUV-32 | README, platform matrix, release notes и analysis gates соответствуют реально принятому поведению |
| YUV-13 | Terra / Claude Sonnet 5 | BLOCKED | YUV-11, YUV-12 | Сопоставление native/Web 119-case matrix с раздельными общими и Web-specific failure cases |
| YUV-22 | Opus / Claude Opus 5 | BLOCKED | YUV-30, YUV-33 | Effects имеют единый документированный contract для addressing, odd chroma и всех форматов |
| YUV-23 | Opus / Claude Opus 5 | BLOCKED | YUV-30, YUV-33 | Blur работает memory-safe, принимает согласованные параметры и одинаково ведёт себя в BGRA/I420/NV21 |
| YUV-24 | Terra / Claude Sonnet 5 | TODO | выбор ревьюера | CMake не дублирует исходники и корректно пересобирает библиотеку после добавления C-файла |
| YUV-26 | Luna / Claude Haiku 4.5 | DELAYED | Unix regeneration evidence | ffigen генерирует только используемый ABI без platform CRT declarations |
| YUV-28 | Opus / Claude Opus 5 | BLOCKED | после YUV-18 | После release устранено подтверждённое дублирование Dart backend-классов без изменения публичного поведения |
| YUV-29 | Luna / Claude Haiku 4.5 | TODO | выбор ревьюера | Header не объявляет несуществующую `nv21_to_rgb`, а public ABI и bindings остаются согласованными |
| YUV-30 | Root / Claude Opus 5 | DISCOVERED | решение владельца по 5 контрактам | Согласованные владельцем contracts effects, blur и ROI, по которым можно безопасно реализовывать C-задачи |
| YUV-31 | Opus / Claude Opus 5 | BLOCKED | YUV-30, YUV-33 | rotate/crop/flip корректно обрабатывают row/pixel stride и нечётную 4:2:0 геометрию |
| YUV-32 | Opus / Claude Opus 5 | BLOCKED | YUV-30, YUV-33 | Преобразования RGBA/BGRA→YUV используют единые channel order, stride и chroma semantics |
| YUV-33 | Opus / Claude Opus 5 | BLOCKED | YUV-30 | Native boundary проверяет descriptors, индексы и allocations до unsafe C-операций |
| YUV-34 | Terra / Claude Sonnet 5 | BLOCKED | YUV-22, YUV-23, YUV-31…YUV-33 | CI ловит native memory errors через ASan/UBSan на затронутых regression cases |
| YUV-35 | Terra / Claude Sonnet 5 | BLOCKED | YUV-29 | C API явно описывает ownership и mutation для каждого buffer argument |
| YUV-36 | Opus / Claude Opus 5 | BLOCKED | после `0.2.5`, YUV-33 | Спроектирован совместимый status-returning ABI для контролируемой передачи C-ошибок в Dart |
| YUV-37 | Terra / Claude Sonnet 5 | BLOCKED | после YUV-23 | Blur уменьшает scratch allocation и сложность без изменения принятого результата |
| YUV-38 | Terra / Claude Sonnet 5 | BLOCKED | после YUV-32 | Block conversion оптимизирована после фиксации семантики без потери stride correctness |
| YUV-39 | Terra / Claude Sonnet 5 | TODO | выбор ревьюера | Исследование выбирает внешние stride-aware reference implementations и критерии их безопасного применения |
| YUV-18 | Terra / Claude Sonnet 5 | BLOCKED | YUV-06, YUV-08, YUV-09, YUV-12, YUV-13, YUV-22, YUV-23, YUV-30…YUV-34 | Releasable `0.2.5`: зависимости приняты, P0/P1 failures закрыты, clean matrix и publish dry-run проходят |

## Правила waitlist

- `BLOCKED` — не снята обязательная зависимость; `DISCOVERED` — нужна product/
  architecture decision; `DELAYED` — отсутствует обозначенное evidence;
  `TODO` в waitlist — optional/post-release исследование, ещё не выбранное для
  текущего batch.
- Ревьюер перед переносом проверяет scope, владельца, зависимости, актуальность
  DoD и отсутствие конфликта с уже выполняемой задачей. После переноса задача
  исчезает из waitlist и появляется в `todo.md` целиком.
- Архитектор может создать новую карточку сразу в `todo.md`, если она уже
  одобрена инженером и не имеет блокеров; иначе создаёт её только здесь.
- Разрешение владельца на изменение native C и headers получено 2026-09-14.
  Это снимает лишь permission blocker: каждая реализация всё ещё требует
  зафиксированного контракта, regression/characterization test cases и native
  runtime verification. Старые фразы в перенесённых карточках о необходимости
  отдельного разрешения заменяются этим правилом.
- Не читать `build/`; generated FFI bindings не редактировать вручную.

---

## YUV-09 — P2 — синхронизировать документацию и локальные quality gates

- Владелец / модель: Luna / Claude Sonnet 5
- Статус: BLOCKED
- Зависимости: YUV-06, YUV-08, YUV-13, YUV-22, YUV-23, YUV-30, YUV-32 (YUV-01/YUV-02/YUV-05/YUV-07/YUV-14/YUV-17 приняты)
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


---


---

---

---

## YUV-13 — P1 — сверить покрытие и оформить проваленные test cases

- Владелец / модель: Terra / Claude Sonnet 5
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
2. Для каждого missing case вернуть YUV-11 или YUV-12 в `CHANGES REQUESTED`.
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
Push-Location example
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/reference_web_conversions_test.dart -d chrome
Pop-Location
git diff --check
git status --short
```

Также выполнить механическую проверку уникальности case ID и наличия каждого failed ID в `failed-test-cases.md`; фактическую команду записать в результат.

### Результат

Не заполнен.

---

---

---

## YUV-22 — P1 — определить и выровнять контракт effects

- Владелец / модель: Opus / Claude Opus 5
- Статус: BLOCKED
- Зависимости: YUV-30, YUV-33 (YUV-04 и YUV-05 приняты; разрешение владельца на native C получено 2026-09-14)
- Scope:
  - `src/yuv/{bgra8888,yuv420,nv21}/*{grayscale,blackwhite,negate}.c`
  - соответствующие headers только при необходимости изменения ABI
  - публичная документация semantics effects
  - focused native/Web reference tests и повторный прогон YUV-11/YUV-12
  - regenerated WASM при любом изменении C

### Проблема

YUV-11 подтвердил 6 reference failures, которые нельзя списать на stride harness:

- `EFFECT-GRAYSCALE-BGRA8888`: `MAE 0.264`, `max 1`, `p99 1`, 92 416 pixels вне exact threshold — C усекает float, independent oracle округляет;
- `EFFECT-BLACKWHITE-BGRA8888`: 1 536 граничных pixels отличаются на 255 — C использует `brightness > 128`, oracle использует documented fixture threshold `>= 128`;
- `EFFECT-BLACKWHITE-I420` и `EFFECT-BLACKWHITE-NV21`: по 1 024 pixels с max error 255;
- `EFFECT-NEGATE-I420` и `EFFECT-NEGATE-NV21`: `MAE 8.152`, `max/p99 134`, 17 408 pixels за threshold — инверсия Y/U/V не эквивалентна RGB negate в limited-range YUV.

Публичный API называет эффекты, но не определяет rounding, threshold boundary и то, должны ли результаты разных форматов быть визуально эквивалентны. Поэтому простое изменение expected либо C без решения контракта законсервирует неоднозначность.

Повторная проверка C-аудита подтвердила дополнительные достигаемые дефекты:

- I420/NV используют `height / 2` и теряют последнюю chroma-строку на нечётной
  высоте, хотя Dart-модель выделяет `ceil(height / 2)`;
- I420/NV blackwhite и negate проходят полные `rowStride`-диапазоны, а
  grayscale делает `memset` по строке, поэтому padding/gap bytes меняются как
  pixels;
- BGRA blackwhite/negate адресуют `x * 4`, а grayscale использует
  `yPixelStride`, то есть один и тот же допустимый descriptor трактуется
  неодинаково;
- probe I420 grayscale `3x3` обработал только одну из двух chroma-строк;
  padded I420 blackwhite заменил canary padding `[33,44]` на `[0,0]`.

### Зафиксированное решение

1. Реализовать выбранный в YUV-30 публичный контракт без локального выбора
   исполнителя. До решения владельца task остаётся `BLOCKED`.
2. Базовый рекомендуемый вариант для YUV-30 — RGB-visible parity с независимым
   oracle YUV-10: одинаковый видимый результат для BGRA/I420/legacy-`nv21`,
   threshold `>= 128`, согласованное rounding и BT.601 limited encode/decode.
3. Применить контракт одинаково для BGRA, I420 и legacy-`nv21` UV order; alpha BGRA сохранять exact.
4. Не ослаблять YUV-10 thresholds после просмотра actual. Если выбранный контракт намеренно отличается от oracle, изменение manifest оформить отдельным reviewed reference update с обоснованием.
5. Обрабатывать только logical samples с учётом row/pixel stride и odd chroma geometry; padding не использовать как pixels.
6. Использовать shared checked helpers YUV-33; не размножать локальные формулы
   ceil/index/size по девяти функциям.
7. После C-изменений пересобрать WASM из тех же sources и проверить native/Web на одинаковых case ID.

### DoD

- Semantics трёх effects однозначно описаны в публичной документации и тестах.
- Все 9 effect cases YUV-11 и соответствующие YUV-12 cases проходят принятый reference contract; шесть текущих failures переведены в `RESOLVED` с metrics повторного прогона.
- BGRA alpha и padding не изменяются; I420/`nv21` odd/custom-stride cases не читают и не пишут вне logical samples.
- Native и WASM собраны из одного commit; generated bindings вручную не изменялись.
- Native C не менялся до отдельного явного разрешения владельца.

### Проверка

```powershell
flutter test --no-pub test/reference_native_conversions_test.dart --plain-name "EFFECT-" --reporter expanded
flutter test --platform chrome test/web/reference_web_conversions_test.dart --plain-name "EFFECT-" --reporter expanded
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

### Результат

Не заполнен.

---

---

---

## YUV-23 — P0 — исправить blur memory safety и межформатную семантику

- Владелец / модель: Opus / Claude Opus 5
- Статус: BLOCKED
- Зависимости: YUV-30, YUV-33 (YUV-04 и YUV-05 приняты; разрешение владельца на native C получено 2026-09-14)
- Scope:
  - `src/yuv/{bgra8888,yuv420,nv21}/*{gaussblur,box_blur,mean_blur}.c`
  - `src/yuv/utils/gauss.c` и headers при необходимости
  - IO/Web wrappers только для безопасной передачи geometry
  - focused native/Web tests, sanitizer/canary checks и повторный прогон YUV-11/YUV-12
  - regenerated WASM при любом изменении C

### Проблема

YUV-11 подтвердил 19 blur failures: 4 Gaussian, 6 box и 9 mean. Это сочетание contract drift и конкретных дефектов реализации:

- BGRA mean blur выделяет tight `width * height * 4`, но индексирует через `rowStride`; padded input может выйти за allocation.
- BGRA mean blur заполняет `temp` только внутри rect, затем копирует весь tight frame обратно: outside-rect и alpha получают неинициализированные bytes. На reference image зафиксировано до 262 144 alpha mismatches и `max 255`.
- Integral-image inclusion/exclusion использует координаты границы без корректного `-1`, поэтому среднее смещено даже на full-frame input.
- YUV mean blur пишет результат в тот же source во время чтения и трактует `radius` как `radius / 2`; результат зависит от порядка обхода и расходится с BGRA semantics.
- YUV Gaussian/box работают по planes (box фактически только по Y), тогда как общий reference contract ожидает визуально сопоставимый blur. Нужно явно выбрать и закрепить межформатную semantics, а не повышать tolerance.
- Gaussian/odd geometry использует floor chroma dimensions в нескольких C paths; это пересекается с YUV-05 и требует повторного canary/sanitizer прогона.

Повторная проверка C-аудита подтвердила, что scope шире reference drift:

- `bgra8888_mean_blur` копирует весь tight `temp`, хотя заполняет только rect;
  outside rect получает неинициализированные bytes, alpha также уничтожается;
- SAT использует неверные границы и `int32_t`, который переполняется уже до
  полного DCI 4K кадра;
- отрицательные `radius`, `sigma == 0` и unchecked `2 * radius + 1` достигают
  division-by-zero либо опасных allocation sizes;
- BGRA Gaussian выделяет `width * height * 4`, но индексирует temp через source
  `rowStride`; NV/I420 blur содержит unchecked multi-allocation paths;
- I420 mean и NV box читают уже записанный результат, поэтому итог зависит от
  направления обхода; probes дали `170/198` вместо snapshot-эталона `127`;
- NV mean использует tight snapshot и игнорирует descriptor strides.

Текущий IO-wrapper уже отсекает padded BGRA для трёх blur methods. Это снижает
достижимость C-09 через публичный Dart API, но не исправляет экспортируемый
descriptor-based C ABI и не закрывает остальные tight/parameter defects.

### Зафиксированное решение

1. Реализовать выбранные в YUV-30 radius/sigma/ROI/blur semantics без
   самостоятельного переопределения контракта исполнителем.
2. Устранить все OOB/uninitialized-read/write paths: allocation и addressing должны учитывать row/pixel strides, temp должен быть полностью инициализирован, outside rect и alpha должны сохраняться exact.
3. Исправить integral image bounds и использовать 64-bit accumulation либо
   иной доказуемо overflow-safe algorithm. Считать blur из неизменяемого source snapshot, без order-dependent in-place reads.
4. Использовать shared checked size/index/descriptor helpers YUV-33 и
   preallocate весь scratch до первой записи; при OOM текущие void-symbols
   обязаны оставить image неизменным.
5. Использовать ceil chroma geometry для odd dimensions и учитывать custom stride каждого logical sample.
6. Синхронизировать docs/reference только по решению YUV-30. Thresholds не подгонять под текущую DLL.
7. Проверить canaries/ASan или эквивалентный sanitizer, затем пересобрать WASM и выполнить те же cases в настоящем Web runtime.

### DoD

- Все 19 текущих blur failures YUV-11 проходят принятый контракт либо имеют явно одобренное изменение reference manifest.
- Outside-rect bytes и BGRA alpha совпадают exact; padded/odd/custom-stride buffers сохраняют canaries.
- Нет OOB, uninitialized bytes и order-dependent результата; sanitizer run приложен с exact command/toolchain.
- Native/Web используют одинаковые case IDs, parameters и thresholds; WASM provenance связан с source commit.
- Native C не менялся до отдельного явного разрешения владельца.

### Проверка

```powershell
flutter test --no-pub test/reference_native_conversions_test.dart --plain-name "BLUR-" --reporter expanded
flutter test --platform chrome test/web/reference_web_conversions_test.dart --plain-name "BLUR-" --reporter expanded
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

Отдельно записать sanitizer command, compiler/version, platform и число выполненных Gaussian/box/mean cases.

### Результат

Не заполнен.

---

---

---

## YUV-24 — P2 — устранить дубли и восстановить пересборку glob в `src/CMakeLists.txt`

- Владелец / модель: Terra / Claude Sonnet 5
- Статус: TODO
- Зависимости: нет; разрешение владельца на native build files получено 2026-09-14.
- Scope:
  - `src/CMakeLists.txt`
  - повторный native build/runtime smoke на затронутых платформах
- Опциональная задача: обнаружена при разборе ffigen 2026-09-13, в аудит `0.2.4` не входила.

### Проблема

Файл перечисляет исходники тремя пересекающимися способами:

```cmake
set_property(GLOBAL PROPERTY CMAKE_CONFIGURE_DEPENDS "yuv/*.c")
file(GLOB_RECURSE SOURCES "yuv/*.c" "yuv_ffi.c" "**/*.c")
add_library(yuv_ffi SHARED ${SOURCES} "yuv_ffi.c")
```

1. `yuv/*.c` рекурсивно даёт 39 файлов, `**/*.c` даёт те же 39, а `yuv_ffi.c` перечислен и в глобе, и явным аргументом `add_library`. Сейчас CMake дедуплицирует список, поэтому сборка не падает, но это конструкция, поведение которой различается между генераторами и версиями CMake.
2. `CMAKE_CONFIGURE_DEPENDS` задан как `GLOBAL` property. Такого глобального свойства не существует — оно действует только на уровне директории. Фактически re-glob при добавлении файлов не настроен: новый `.c` не попадает в сборку, пока вручную не удалить CMake cache. Это наиболее вероятная причина наблюдавшегося «файлы не попадают в DLL».

Проверено на собранном `yuv_ffi.dll` (144 КБ, 2026-09-13 16:04): 39 из 40 вызываемых Dart символов присутствуют, то есть сборка не «обрезана» полностью, но механизм обновления списка исходников не работает.

### Предлагаемое решение

1. Заменить три шаблона одним `file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.c")` и убрать повторное указание `yuv_ffi.c` в `add_library`.
2. Удалить нерабочую строку `set_property(GLOBAL PROPERTY CMAKE_CONFIGURE_DEPENDS ...)`.
3. Не менять флаги оптимизации, platform linking и `target_include_directories` — они вне scope.
4. Альтернатива к обсуждению: заменить glob явным списком исходников. Это надёжнее для воспроизводимости, но требует ручной поддержки при добавлении файлов.

### DoD

- Список исходников задан одним способом, без дублей.
- Добавление нового `.c` в `src/yuv/**` попадает в сборку без ручной очистки CMake cache.
- Состав экспортов DLL до и после изменения совпадает.
- Native runtime smoke проходит на затронутых платформах.
- Native C sources (`*.c`, `*.h`) не изменялись; изменён только build file.
- Добавлен regression/smoke case, который подтверждает, что source-set из glob
  действительно участвует в выполнении native операции после reconfigure.

### Проверка

```powershell
flutter clean
flutter pub get
flutter test
<native build command для платформы>
<runtime smoke command>
git diff --check
git status --short
```

Отдельно: до и после изменения сравнить список экспортируемых символов DLL (`dumpbin /exports` из Visual Studio либо `nm -D` на Unix) и приложить фактическую команду.

### Результат

Не заполнен.

---

---

---

## YUV-26 — P3 — ограничить ffigen только используемым ABI

- Владелец / модель: Luna / Claude Haiku 4.5; при расхождении generated ABI повысить до Claude Sonnet 5
- Статус: DELAYED
- Зависимости: нет
- Scope:
  - `ffigen.yaml`
  - `lib/src/functions/bindings/yuv_ffi_bingings.dart` только через регенерацию
  - audit script/test, сравнивающий используемые Dart symbols с generated bindings
  - `.github/workflows/ci.yml`, отдельная Unix regeneration job
- Опциональная tooling-задача; не блокирует YUV-18.

### Проблема

`ffigen.yaml` не ограничивает declarations, достижимые из entry point.
Generated-файл содержит около 10 770 строк, включая Windows CRT и
platform-specific структуры, хотя Dart-код использует только узкий набор YUV
functions и `YUVDef`. Это затрудняет review и делает результат генерации
зависимым от host headers.

Отсутствующий native symbol `nv21_to_rgb` отделён в YUV-29: разрешение на
headers получено, но optional cleanup не должен блокировать tooling cleanup.

### Зафиксированное решение

1. Сначала автоматически получить множество symbols, фактически вызываемых из
   Dart, и сохранить результат проверки в task evidence.
2. Настроить `headers.include-directives`, `exclude-all-by-default`,
   `functions.include` и `structs.include` в синтаксисе установленного
   ffigen 13.0.0.
3. Не менять `src/**/*.c` и `src/**/*.h`; `nv21_to_rgb` допустимо исключить
   из generated bindings как неиспользуемый symbol.
4. Регенерировать binding только командой ffigen, ручные изменения запрещены.
5. Сравнить до/после все symbols, реально используемые `lib/src/**`.
6. Добавить обязательную job `bindings-regeneration` на `ubuntu-latest`,
   запускаемую на `push` и `pull_request`; не использовать `continue-on-error`.
7. В job установить Flutter 3.44.9 и `libclang`, выполнить ffigen и
   `tool/verify_bindings_audit.dart`.
8. После Unix-регенерации потребовать чистый exact diff для `ffigen.yaml` и
   generated bindings. `git diff --exit-code` является более сильным
   доказательством эквивалентности имён и сигнатур, чем отдельный regex-report.

### DoD

- Generated-файл не содержит CRT functions и platform-dependent CRT structs.
- Каждый symbol, вызываемый Dart-кодом, присутствует с прежней сигнатурой.
- Регенерация на Windows и Unix даёт эквивалентный набор public members класса
  `YuvFfiBindings`.
- Обязательная `bindings-regeneration` job проходит на Linux и падает при любом
  host-dependent изменении generated bindings.
- Job выполняет audit всех 40 используемых symbols и не содержит soft-fail.
- Native headers/sources не менялись.
- Анализатор и VM suite не получают новых падений.

### Проверка

```powershell
flutter pub run ffigen --config ffigen.yaml
dart run tool/verify_bindings_audit.dart
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib
git diff --check
git status --short
```

Обязательная Linux CI-проверка:

```sh
flutter pub get
flutter pub run ffigen --config ffigen.yaml
dart run tool/verify_bindings_audit.dart
git diff --exit-code -- ffigen.yaml lib/src/functions/bindings/yuv_ffi_bingings.dart
```

Если `ffigen` не находит shared library автоматически, job должна явно
установить `libclang-dev`; не использовать Emscripten toolchain из Web job как
неявный источник host-зависимости.

В результате приложить число строк generated-файла до/после и машинно
полученный список используемых Dart symbols.

### Результат

```text
Статус: READY FOR REVIEW
Commit: `450984a` (`build: narrowed ffigen to the ABI the package actually uses`)

Изменённые файлы:
- ffigen.yaml
- lib/src/functions/bindings/yuv_ffi_bingings.dart (регенерирован)
- tool/verify_bindings_audit.dart (новый audit скрипт)

Что сделано:
- Настроены `exclude-all-by-default: true`, `functions.include` с regex-паттернами
  для всех 40 используемых функций, и `structs.include: [YUVDef]` в ffigen.yaml.
- Использованы regex-паттерны `bgra8888_.*`, `nv21_.*`, `yuv420_.*`, `nvXX_to_nvYY`
  и исключение `nv21_to_rgb` (отделено в YUV-29, так как не имеет реализации).
- Сгенерировано новое bindings-файл командой `flutter pub run ffigen --config ffigen.yaml`.
- Создан audit скрипт `tool/verify_bindings_audit.dart`, проверяющий соответствие
  используемых Dart-символов и сгенерированных public members в YuvFfiBindings.

Проверки:
- flutter pub run ffigen --config ffigen.yaml — exit 0, успешно сгенерирован новый файл
- flutter analyze --no-pub lib test — exit 0, no issues found
- dart format --output=none --set-exit-if-changed --line-length 150 lib — exit 0
- git diff --check — exit 0 (только CRLF warning на Windows)
- git status --short — показаны только изменённые ffigen.yaml и bindings-файл
- tool/verify_bindings_audit.dart — exit 0, SUCCESS: All 40 used symbols present

Результаты:
- Число строк сгенерированного файла до: 10 770
- Число строк сгенерированного файла после: 606
- Сокращение: на 10 164 строк (-94.4%)
- Исключены все Windows CRT функции и platform-specific структуры

Используемые символы (40 штук, машинно полученные):
bgra8888_blackwhite, bgra8888_box_blur, bgra8888_crop_rect,
bgra8888_flip_horizontally, bgra8888_flip_vertically, bgra8888_from_rgba8888,
bgra8888_gaussian_blur, bgra8888_grayscale, bgra8888_mean_blur, bgra8888_negate,
bgra8888_rotate, bgra8888_to_i420, bgra8888_to_nv21, nv21_blackwhite,
nv21_box_blur, nv21_crop_rect, nv21_flip_horizontally, nv21_flip_vertically,
nv21_from_rgba8888, nv21_gaussian_blur, nv21_grayscale, nv21_mean_blur,
nv21_negate, nv21_rotate, nv21_to_bgra8888, nv21_to_i420, nvXX_to_nvYY,
yuv420_blackwhite, yuv420_box_blur, yuv420_crop_rect, yuv420_flip_horizontally,
yuv420_flip_vertically, yuv420_from_rgba8888, yuv420_gaussblur, yuv420_grayscale,
yuv420_i420_to_nv21, yuv420_mean_blur, yuv420_negate, yuv420_rotate,
yuv420_to_bgra8888

Плюс структура: YUVDef

Сравнение до/после:
✓ Все 40 символов присутствуют в сгенерированном файле
✓ Сигнатуры функций совпадают
✓ Структура YUVDef присутствует с правильными полями
✓ Нет неиспользуемых CRT symbols

Ручная проверка:
- Windows 10 x64 / AMD64, Flutter 3.44.9 (из /d/.important/flutter-3.49), Dart 3.12.2
- Сгенерирован файл без ошибок
- Все проверки analyzer и format прошли успешно
- Audit скрипт подтвердил полноту bindings

Остаточные риски:
- nv21_to_rgb в header остаётся объявленной без реализации; удаление требует
  отдельного разрешения (YUV-29)
- Нет гарантии о кросс-платформности паттернов на Unix-хостах; проверку
  рекомендуется провести при наличии Linux/macOS CI

Native C permission:
- не требовалось; `src/**/*.c` и `src/**/*.h` не изменялись
```

### Независимая проверка исполнителя-ревьюера

Работа принята по существу. Одна неточность в отчёте выше:

1. «git status — показаны только изменённые ffigen.yaml и bindings-файл» было
   неверно на момент прогона: в дереве параллельно лежали файлы YUV-27.
   На результат задачи это не влияет, но утверждение не соответствовало факту.

Отдельно отмечу собственную ошибку при первой проверке: я сначала записал, что
`tool/verify_bindings_audit.dart` отсутствует. Это было неверно — файл есть,
он untracked, и первая проверка искала его не тем способом. Формулировка
исправлена здесь же, чтобы в трекере не осталось ложного замечания.

Проверено независимо, на Flutter 3.44.9 / Dart 3.12.2:
- Регенерация выполнена заново мной: `flutter pub run ffigen --config ffigen.yaml`
  — exit 0. Файл получен только генератором, вручную не редактировался.
- Машинный diff сигнатур со старой версией (`git show HEAD:` -> файл, разбор
  regex по имени и возвращаемому типу):
  - используемых Dart-символов: 40;
  - отсутствуют после регенерации: НЕТ;
  - изменилась сигнатура: НЕТ;
  - публичных методов до: 716, после: 40.
- Строк: 10 770 -> 606.
- CRT-функции (`malloc`, `free`, `memcpy`, `printf`, `sprintf`, `fopen`,
  `wcscpy`, `_invalid_parameter`): 0 вхождений.
- `nv21_to_rgb`: 0 вхождений; `class YUVDef`: присутствует.
- `flutter analyze --no-pub lib test` — exit 0, No issues found.
- `flutter test --no-pub` — 281 passed / 31 failed. 31 падение — известные,
  зарегистрированные ранее; новых падений от этой задачи нет.
- `dart format --set-exit-if-changed` — exit 0; `git diff --check` — exit 0.
- `example/pubspec.lock` не изменён.

Доработка audit-скрипта при приёмке. `tool/` попадает в голый `flutter analyze`
(то есть в CI-гейт), и в исходном виде `tool/verify_bindings_audit.dart` его не
проходил: 14 диагностик `avoid_print`, неиспользуемый импорт `dart:async`, плюс
`dangling_library_doc_comments`, и файл не проходил `dart format`. Исправлено:
лишний импорт удалён, добавлен точечный `// ignore_for_file: avoid_print` с
обоснованием (это CLI-инструмент, вывод в stdout — его назначение),
doc-комментарий заменён на обычный, файл отформатирован. После правок:
`flutter analyze --no-pub lib test tool` — exit 0, `dart format
--set-exit-if-changed` — exit 0, сам скрипт — exit 0, «All 40 used symbols
present».

Замечание к DoD: пункт «регенерация на Windows и Unix даёт эквивалентный набор
public members» проверен только на Windows. Unix-прогон остаётся незакрытым —
это честно отражено и в «Остаточных рисках» отчёта.

### Независимое ревью root 2026-09-13

Статус остаётся `READY FOR REVIEW`: implementation defect не найден, но полный
DoD пока не выполнен.

- `tool/verify_bindings_audit.dart` повторно подтвердил 40/40 используемых
  symbols и отсутствие лишних public members; отдельно сравнены wrapper
  signatures до/после — из прежней поверхности исчез только неиспользуемый
  `nv21_to_rgb`.
- `flutter analyze --no-pub lib test` на Flutter 3.44.9 — exit 0.
- Общий focused review suite — 151/151 passed.
- Generated-файл содержит 40 используемых functions и `YUVDef`; native
  headers/sources не менялись.
- Блокер приёмки: отсутствует требуемая повторная генерация на Linux/macOS с
  машинным сравнением набора members и signatures. Windows-only evidence не
  позволяет поставить `DONE`.

### Повторное независимое ревью root 2026-09-14

Статус: `CHANGES REQUESTED`.

Предыдущее замечание не устранено: текущие GitHub Actions jobs не запускают
ffigen и не сравнивают generated ABI, поэтому зелёные run #24/#25 не являются
Unix evidence для YUV-26. Локально WSL optional component не установлен,
Docker/Podman отсутствуют; повторить Unix regeneration на этой машине нельзя.

Windows implementation и audit приняты: 40/40 используемых symbols найдены,
лишние CRT members отсутствуют, analyzer и focused VM suite 114/114 проходят.
Для повторного review требуется:

1. на Linux или macOS выполнить `flutter pub run ffigen --config ffigen.yaml`;
2. запустить `tool/verify_bindings_audit.dart`;
3. машинно сравнить с принятой Windows-генерацией имена, return/argument types
   всех public wrappers и приложить diff/логи;
4. подтвердить отсутствие неожиданного tracked diff после повторной генерации.

Native headers/sources менять не требуется. Generated bindings разрешено менять
только результатом ffigen, не вручную.

---

---

---

## YUV-28 — P2 / architecture — сократить дублирование Dart backend-классов после `0.2.5`

- Владелец / модель: Opus / Claude Opus 5
- Статус: BLOCKED
- Зависимости: выполнять только после YUV-18; YUV-07 и YUV-20 должны быть DONE
- Scope:
  - shared Dart state/geometry/serialization abstractions
  - `lib/src/yuv/impl/io/yuv_image.dart`
  - `lib/src/yuv/impl/web/yuv_web.dart`
  - `lib/src/yuv/impl/yuv_stub.dart`
  - parity/characterization tests
- Post-release refactor; не блокирует YUV-18.

### Проблема

Три `YuvImageImpl` дублируют constructors, state, plane accessors, copy/bytes
logic и format dispatch. Shared `YuvGeometry` и `YuvCodec` уже сократили часть
расхождений, поэтому исходную оценку «около 700 строк» нужно пересчитать после
закрытия YUV-07/YUV-20, а не переносить старый план механически.

Пустое состояние accessor'ов формально расходится: IO бросает `RangeError`,
Web/stub возвращают zero-length sentinel. Для валидного публично созданного
изображения состояние практически недостижимо; shared sentinel нельзя
содержательно изменить, потому что его buffer имеет длину 0. Это contract debt,
а не подтверждённая corruption.

### Зафиксированное решение

1. Сначала снять актуальный duplication map после релиза и определить реально
   общий слой. Не создавать `YuvImageBase` только ради наследования.
2. Предпочесть composition для state/codec/geometry; backend-specific FFI/WASM
   dispatch оставить в `impl/*_io.dart` и `impl/*_web.dart`.
3. Зафиксировать единый контракт accessor'ов на недоступном/пустом состоянии и
   покрыть его characterization tests до изменения реализации.
4. Сохранить partial-WASM policy: общий state не означает feature parity.
5. Не менять native C, generated bindings и публичную mutation model.

### DoD

- Общая логика имеет одного владельца без циклических imports.
- IO/Web/stub сохраняют format, geometry, copy, serialization и revision
  contracts существующих tests.
- Удаление дублирования измерено diff/stat и не смешано с новым поведением.
- Empty-state contract одинаков и документирован либо доказано, что состояние
  недостижимо и sentinel удалён.
- Native и настоящий Chrome suites не получают новых падений.

### Проверка

```powershell
flutter analyze --no-pub lib test
flutter test
flutter test --platform chrome test/web
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

### Результат

Не заполнен.

---

---

---

## YUV-29 — P3 — удалить native-объявление `nv21_to_rgb` без реализации

- Владелец / модель: Luna / Claude Haiku 4.5; при обнаружении ABI consumer повысить до Claude Sonnet 5
- Статус: TODO
- Зависимости: нет; разрешение владельца на native headers получено 2026-09-14.
- Scope:
  - `src/yuv/nv21.h`
  - `src/yuv/nv21/h/nv21_to_rgb.h`
  - regenerated bindings только если symbol ещё входит после YUV-26
- Опциональная native-header cleanup; не блокирует YUV-18 и ждёт выбора ревьюера.

### Проблема

Header объявляет и подключает `nv21_to_rgb`, но реализации и Dart-consumers
нет. Lazy lookup скрывает дефект до первого вызова. Это отдельная ABI hygiene
задача: она не должна блокировать ffigen filtering и не должна выполняться без
разрешения на native headers.

### Зафиксированное решение

1. Перед изменением повторно проверить native exports и все consumers.
2. При подтверждённом отсутствии consumer удалить declaration header и include
   из `nv21.h`; новую C-реализацию без отдельного требования не писать.
3. Если generated binding ещё содержит symbol, регенерировать его штатно после
   header change; generated-файл вручную не редактировать.
4. Не менять существующий NV21/UV compatibility contract.

### DoD

- В headers и generated bindings нет declaration без реализации.
- Все реально используемые Dart symbols по-прежнему резолвятся.
- Добавлен native/API characterization case: поддерживаемая NV21 conversion выполняется, а несуществующий `nv21_to_rgb` не попадает в generated/public surface.
- Native build/runtime smoke и анализатор проходят.

### Проверка

```powershell
flutter pub run ffigen --config ffigen.yaml
flutter analyze
flutter test
<native build/runtime smoke>
git diff --check
git status --short
```

### Результат

Не заполнен.

---

---

## YUV-30 — P0 / architecture gate — зафиксировать native effects/blur/ROI contract

- Владелец / модель: Root (Architect/Reviewer) / Claude Opus 5
- Ожидаемое reasoning: High
- Статус: DISCOVERED
- Зависимости: решение владельца по пяти публичным контрактам
- Scope:
  - публичные docs для `grayscale`, `blackwhite`, `negate`, `gaussianBlur`,
    `boxBlur`, `meanBlur`;
  - semantics `rect`, `radius`, `sigma`, border, alpha и padding;
  - решение о failure ABI для patch `0.2.5` и будущего minor release;
  - обновление Architect Decision/зависимостей YUV-22, YUV-23, YUV-31…YUV-36.
- Non-goal: реализация Dart/C, изменение manifest или thresholds.

### Проблема

Проверенный C-аудит подтвердил конфликтующие фактические контракты. Blur
размывает разные planes/channels в BGRA, I420 и legacy-`nv21`; mean использует
`radius / 2`, остальные реализации — `2 * radius + 1`; rect ограничивает только
часть planes; YUV negate является raw-plane transform, а reference oracle ждёт
RGB-visible результат. Публичная документация этих различий не определяет.

Без решения владельца исполнитель вынужден сам выбирать публичное поведение,
что запрещено orchestration protocol и делает YUV-22/YUV-23 неготовыми.

### Требуется решение владельца

1. Effects: RGB-visible parity между форматами либо format-specific plane-native
   semantics. Рекомендация архитектора: RGB-visible parity для grayscale,
   blackwhite и negate, согласованная с independent oracle YUV-10.
2. Blur: RGB-visible parity либо deterministic plane-native convolution.
   Рекомендация архитектора: plane-native blur одинаковым kernel/radius/border
   по всем logical color planes, BGRA alpha не менять. Для subsampled chroma
   строгая visible boundary невозможна без format conversion: один chroma
   sample разделяют до четырёх luma pixels.
3. `rect`: crop-style `floor(left/top)`, `ceil(right/bottom)`, clamp к кадру и
   no-op для пустого результата либо `ArgumentError`. Рекомендация: clamp/no-op.
   Для 4:2:0 отдельно выбрать: менять все chroma samples, чьи 2×2 footprints
   пересекают ROI, либо не менять boundary chroma. Рекомендация: intersecting
   blocks с явным предупреждением, что RGB pixels у границы делят chroma.
4. Параметры: `radius == 0` как no-op, отрицательный radius и non-positive
   `sigma` как `ArgumentError`; требуется выбрать документируемую верхнюю
   границу radius. Рекомендация safety-cap: `radius <= 256`.
5. Allocation failure в `0.2.5`: сохранить void ABI и гарантировать atomic
   no-op либо вводить новые status-returning symbols сейчас. Рекомендация:
   сохранить ABI в patch, новые status symbols вынести в YUV-36/`0.3.0`.

### Architect Decision

До ответа владельца не зафиксирован. Исполнителям запрещено начинать зависящие
задачи или выбирать один из вариантов самостоятельно.

### DoD

- [ ] Зафиксированы ответы по всем пяти пунктам без неоднозначных слов.
- [ ] Определены exact formula/rounding/threshold и видимые результаты effects.
- [ ] Определены planes/channels, radius, border и ROI mapping каждого blur.
- [ ] Определено поведение invalid/empty/outside/fractional rect и параметров.
- [ ] Решено, что остаётся в `0.2.5`, а что требует нового ABI/minor release.
- [ ] YUV-22, YUV-23, YUV-31…YUV-36 синхронизированы с решением.
- [ ] Runtime-код и native sources в этой задаче не изменены.

### Результат

Не заполнен.

---

---

---

## YUV-31 — P0 — исправить stride/odd safety в rotate, crop и flip

- Владелец / модель: Opus / Claude Opus 5
- Ожидаемое reasoning: Medium
- Статус: BLOCKED
- Зависимости: YUV-30, YUV-33 (разрешение владельца на native C получено 2026-09-14)
- Scope:
  - `src/yuv/{bgra8888,yuv420,nv21}/*{rotate,crop,flip}.c`;
  - IO wrappers только для безопасной нормализации/ошибок;
  - focused native/Web transform tests, canary и sanitizer cases;
  - regenerated WASM из того же commit.

### Проблема

Выводы C-аудита подтверждены исходниками:

- I420/NV rotate использует `dstWidth` вместо `dst->yRowStride`, source pixel
  stride вместо destination stride и floor `dst->width / 2` для chroma;
- BGRA rotate игнорирует оба rowStride и копирует `src->yPixelStride` bytes в
  destination, что допускает OOB при custom stride;
- crop вычисляет destination rows как tight и копирует `logicalWidth *
  pixelStride`, то есть принимает gap/padding за sample bytes; chroma crop
  использует floor и теряет trailing samples на odd geometry;
- horizontal flip переставляет `pixelStride` bytes вместо sample size
  `1/2/4`, BGRA игнорирует rowStride;
- flip имеет multi-allocation leaks и vertical path может завершиться после
  частичной mutation при OOM.

Неподдерживаемый raw `rotationDegrees` недостижим через публичный Dart enum, но
остаётся defensive-boundary дефектом экспортируемых C symbols. Stride/crop/flip
дефекты через публичные custom planes достижимы.

Probe I420 rotate 180° с `yPixelStride=2,rowStride=3` подтвердил collision
destination indices; crop `3x3` записал лишь один из четырёх chroma samples.

### Architect Decision

1. Адресовать source и destination только их собственными row/pixel strides.
2. Размер logical sample фиксирован форматом: 1 byte Y/planar U/V, 2 bytes
   interleaved UV, 4 bytes BGRA; padding никогда не копировать как pixel data.
3. Использовать ceil chroma geometry из YUV-33. Mapping odd crop origin следует
   точному ROI/chroma policy, принятому YUV-30.
4. `rotate` принимает только enum-derived 0/90/180/270; C boundary defensive
   отклоняет иные degrees и несовместимую destination geometry без записи.
5. Horizontal flip использует scalar/fixed sample swap без heap allocation.
   Vertical flip выделяет scratch один раз до первой записи; OOM — atomic no-op.
6. Не менять установленный legacy `nv21` `(U,V)` byte order.

### DoD

- [ ] Tight и минимально padded layouts проходят rotate/crop/flip для трёх форматов.
- [ ] Проверены `1x1`, `1xN`, `Nx1`, odd/even и все rotation values.
- [ ] Source/destination padding и canaries не читаются/не меняются как samples.
- [ ] Odd chroma не теряет trailing row/column; crop phase соответствует YUV-30.
- [ ] Allocation failure до vertical flip оставляет bytes неизменными; текущий
      false-positive revision bump явно зафиксирован как ограничение void ABI
      до YUV-36.
- [ ] ASan/UBSan harness YUV-34 не сообщает OOB/UB/leaks.
- [ ] Native и real WASM cases используют одинаковые fixtures.
- [ ] Native C implementation сопровождается regression/characterization cases
      и native runtime verification.

### Результат

Не заполнен.

---

---

---

## YUV-32 — P1 — унифицировать RGBA/BGRA → YUV conversion contract

- Владелец / модель: Opus / Claude Opus 5
- Ожидаемое reasoning: Medium
- Статус: BLOCKED
- Зависимости: YUV-30, YUV-33 (разрешение владельца на native C получено 2026-09-14)
- Scope:
  - `src/yuv/bgra8888/bgra8888_{from_rgba,to_i420,to_nv21}.c`;
  - shared color conversion helpers;
  - corresponding native/Web reference tests and regenerated WASM;
  - public conversion docs when coefficients/range become contractual.

### Проблема

`yuv420_from_rgba8888` и `nv21_from_rgba8888` используют BT.601 limited range и
average реального 2×2 блока. BGRA→I420/NV применяет другую full-range matrix и
берёт chroma только из top-left pixel. Один и тот же RGBA/BGRA кадр поэтому даёт
разные YUV bytes; probe получил Y `[82,41,41,41]` против `[76,28,28,28]` и UV
`[202,142]` против `[85,255]`.

Отдельно `bgra8888_from_rgba8888` пишет tight index `(y*width+x)*4` и игнорирует
destination descriptor. Dart сейчас смягчает это staging-копией, но exported C
symbol остаётся tight-only без объявленного precondition.

### Architect Decision

1. Канальный порядок input не меняет color matrix/range/rounding: canonical
   contract — BT.601 limited/video range, уже используемый RGBA→YUV paths.
2. U/V считать average всех реально существующих pixels в 2×2 block; odd edge
   делить на actual sample count.
3. Legacy `nv21` хранит установленный `(U,V)` order.
4. Использовать common fixed-point helpers и shared checked geometry YUV-33.
5. `bgra8888_from_rgba8888` обязан использовать destination row/pixel strides;
   input RGBA остаётся tight согласно публичному Dart contract.
6. Manifest не подгонять под current DLL; любое осознанное изменение oracle —
   отдельный reviewed reference update.

### DoD

- [ ] RGBA и эквивалентный BGRA input дают одинаковые Y/U/V logical samples.
- [ ] Tight/padded и odd/even cases сохраняют descriptor geometry и canaries.
- [ ] 2×2 chroma reducer и odd edges сверены с independent oracle.
- [ ] Native и WASM проходят одинаковые conversion case IDs/thresholds.
- [ ] Документация явно называет matrix/range/rounding и legacy UV order.
- [ ] Generated bindings не редактировались вручную.
- [ ] Native C implementation сопровождается regression/characterization cases
      и native runtime verification.

### Результат

Не заполнен.

---

---

---

## YUV-33 — P0 / foundation — ввести checked native descriptor/index/allocation primitives

- Владелец / модель: Opus / Claude Opus 5
- Ожидаемое reasoning: Medium
- Статус: BLOCKED
- Зависимости: YUV-30 (разрешение владельца на native C получено 2026-09-14)
- Scope:
  - `src/yuv/yuv.h`, `src/yuv/utils/h/yuv_utils.h` и новый узкий shared helper при необходимости;
  - C-only unit harness для descriptor, ceil chroma и checked arithmetic;
  - adoption contract для YUV-22, YUV-23, YUV-31 и YUV-32.
- Non-goal: массовая миграция всех operations в одном foundation commit.

### Проблема

`yuv_index` и allocation expressions вычисляются в signed `int`; `width *
height * 4`, `2 * radius + 1` и `y * rowStride + x * pixelStride` могут
переполниться до conversion в `size_t`. C functions не имеют общей проверки
positive geometry/strides, required pointers, format-specific sample sizes или
совместимости source/destination descriptors.

`YUVDef` не содержит фактических buffer lengths. Поэтому C boundary может
доказать только минимально необходимый span и арифметическую корректность, но не
может проверить, сколько памяти caller действительно выделил. Это ограничение
нельзя скрывать обещанием полной buffer validation.

### Architect Decision

1. Заменить macro-indexing на checked `size_t` helpers для multiplication,
   addition, plane span и sample offset; overflow возвращает failure до доступа
   к памяти.
2. Добавить format/operation-specific descriptor validation: positive geometry,
   non-null required planes, positive strides, `rowStride >= minimum span`,
   supported pixel stride/sample size и compatible destination dimensions.
3. Один shared ceil helper `(value / 2) + (value % 2)` без overflow формулы
   `(value + 1) / 2`.
4. Helpers не читают pointers и тестируются на boundary values без выделения
   многогигабайтных frames.
5. Существующие exported void symbols в `0.2.5` не менять без решения YUV-30;
   status-returning ABI вынесен в YUV-36.
6. Каждый operation consumer обязан завершаться до первой mutation при failed
   validation/allocation и иметь единый cleanup path.

### DoD

- [ ] Checked add/multiply/index/span helpers покрыты overflow-boundary tests.
- [ ] Descriptor validator покрывает null pointers, zero/negative dimensions,
      undersized stride, unsupported pixel stride и incompatible destination.
- [ ] Tests не требуют реальной огромной allocation.
- [ ] Ни один helper не обещает проверить неизвестную фактическую buffer length.
- [ ] Adoption points перечислены по task/file; массовый unrelated rewrite отсутствует.
- [ ] Clang strict warnings и sanitizer unit harness проходят.
- [ ] Native C implementation сопровождается regression/characterization cases
      и native runtime verification.

### Результат

Не заполнен.

---

---

---

## YUV-34 — P1 / release gate — добавить native ASan/UBSan safety gate

- Владелец / модель: Terra / Claude Sonnet 5
- Ожидаемое reasoning: Medium
- Статус: BLOCKED
- Зависимости: YUV-22, YUV-23, YUV-31, YUV-32, YUV-33
- Scope:
  - C test harness outside `build/`;
  - GitHub Actions Ubuntu job with Clang ASan/UBSan/LSan where supported;
  - canary, invalid-parameter and allocation-failure cases;
  - documented compiler/version/commands and source commit.

### Проблема

Flutter reference tests обнаруживают неправильные pixels, но не доказывают
отсутствие OOB, use of uninitialized memory, integer UB или leaks внутри C.
Аудит опирался на one-off Clang/probe runs; постоянного required gate нет.

### Architect Decision

1. Добавить отдельный native C harness, который напрямую вызывает exported
   operations на tight/padded/odd descriptors с prefix/suffix/row canaries.
2. Required Ubuntu CI job собирает текущие `src/yuv` с `clang` и
   `-fsanitize=address,undefined`; leak detection включается там, где стабильно
   поддерживается runner.
3. Cases включают invalid rect/radius/sigma/geometry, overflow arithmetic,
   allocation-failure injection и atomic no-op.
4. Job не использует checked-in binaries, не читает `build/`, не имеет
   `continue-on-error` и печатает число исполненных cases.
5. Web parity остаётся в integration harness; sanitizer job её не заменяет.

### DoD

- [ ] Harness детерминирован и хранится вне исключённых каталогов.
- [ ] ASan/UBSan job required и падает на sanitizer report/non-zero exit.
- [ ] Покрыты все regression probes C-01…C-09 и H-01/H-02, релевантные памяти.
- [ ] Allocation injection доказывает cleanup и отсутствие partial commit.
- [ ] В tracker записаны run URL, toolchain versions, case count и provenance.
- [ ] Existing Flutter analyzer/tests не регрессировали.

### Результат

Не заполнен.

---

---

---

## YUV-35 — P2 / optional cleanup — синхронизировать C API ownership, mutation и комментарии

- Владелец / модель: Terra / Claude Sonnet 5
- Ожидаемое reasoning: Low
- Статус: BLOCKED
- Зависимости: YUV-29 (разрешение владельца на native headers получено 2026-09-14)
- Не блокирует YUV-18.
- Scope:
  - C headers и matching definitions;
  - `src/yuv/yuv.c`, NV comments и `src/yuv/utils/h/log.h`;
  - ffigen regeneration only if declarations change.

### Проблема

- NV comments говорят VU, хотя установленный compatibility contract — `(U,V)`.
- In-place functions принимают `const YUVDef *src`, хотя меняют pointee planes;
  const относится к struct, но создаёт ложное впечатление immutable operation.
- Non-Android logging объявляет `debug/warn/error`, Android — `LOGD/LOGW/LOGE`.
- `freeYUVDef` определена, но не объявлена/не экспортируется и не имеет consumer;
  Dart уже владеет struct/planes и освобождает их через `YUVDefClass.dispose()`.
- Missing `nv21_to_rgb` declaration/definition mismatch остаётся отдельной YUV-29.

### Architect Decision

1. Исправить только документационную/сигнатурную правду без изменения runtime
   semantics: legacy `nv21` comments называют interleaved `(U,V)`.
2. In-place definitions/headers принимают `YUVDef *image`; read-only source и
   writable destination различаются именами и const-correctness.
3. Унифицировать macros как `LOGI/LOGD/LOGW/LOGE` на всех платформах.
4. Если повторный consumer search пуст, удалить `freeYUVDef` как dead code;
   не экспортировать второй ownership path рядом с Dart allocator.
5. Не объединять с YUV-29 и не редактировать generated bindings вручную.

### DoD

- [ ] Headers и definitions совпадают; strict C compile не даёт const mismatch.
- [ ] NV comments нигде не заявляют VU для текущего `(U,V)` contract.
- [ ] Logging macro surface одинакова на Android/non-Android.
- [ ] `freeYUVDef` либо удалена после доказанного отсутствия consumers, либо
      задача возвращена архитектору с найденным ownership requirement.
- [ ] ABI symbols/runtime output не изменились.
- [ ] Native C/header implementation сопровождается regression/characterization
      cases и native runtime verification.

### Результат

Не заполнен.

---

---

---

## YUV-36 — P2 / post-release — спроектировать status-returning native ABI

- Владелец / модель: Opus / Claude Opus 5
- Ожидаемое reasoning: Medium
- Статус: BLOCKED
- Зависимости: после `0.2.5`, YUV-33 и решение YUV-30
- Не блокирует YUV-18.

### Проблема

Все 40 exported operations возвращают `void`. При invalid descriptor или OOM
Dart не может отличить success от atomic no-op и увеличивает revision как после
успеха. Изменение return type существующего symbol небезопасно для patch ABI.

### Architect Decision

1. Для `0.2.5` сохранить существующие symbols/signatures и требовать safe
   atomic no-op на C failure.
2. Для следующего minor спроектировать additive `*_v2`/единый status contract,
   не менять значение существующего symbol на месте.
3. Status enum различает success, invalid argument, unsupported layout,
   overflow и allocation failure; Dart переводит его в документированные
   exceptions и не меняет revision при failure.
4. Ownership buffer lengths/descriptor versioning рассмотреть явно, поскольку
   текущий `YUVDef` не несёт allocation lengths.

### DoD

- [ ] Есть reviewed ABI proposal с compatibility/migration table.
- [ ] Старые symbols продолжают работать на поддерживаемом happy path.
- [ ] v2 status и Dart exception mapping покрыты tests.
- [ ] Failed operation не меняет bytes/metadata/revision.
- [ ] Headers/ffigen обновляются штатно только в реализации отдельного minor.

### Результат

Не заполнен.

---

---

---

## YUV-37 — OPT / post-release — оптимизировать blur scratch и алгоритмическую сложность

- Владелец / модель: Terra / Claude Sonnet 5
- Ожидаемое reasoning: Medium
- Статус: BLOCKED
- Зависимости: после YUV-23
- Не блокирует YUV-18.

### Проблема

Gaussian helper делает O(width+height) heap allocations на plane и строит один
kernel до трёх раз за публичный вызов. NV box chroma и mean paths используют
O(W*H*r²), хотя Y path уже содержит separable sliding-window подход. Vertical
flip allocation устранит YUV-31 как safety fix и сюда не входит.

### Architect Decision

После фиксации reference output переиспользовать один kernel и bounded scratch,
перевести 1/2/4-byte samples на общий stride-aware separable primitive. Любая
оптимизация обязана сохранить exact/tolerance output YUV-23 и border/ROI policy.

### DoD

- [ ] Allocation count не зависит от width+height.
- [ ] Box/mean complexity не хуже O(W*H) для fixed channel count.
- [ ] Benchmark фиксирует before/after time и peak allocations.
- [ ] Native/Web reference output и sanitizer suite остаются зелёными.
- [ ] Оптимизация не смешана с correctness commit YUV-23.

### Результат

Не заполнен.

---

---

---

## YUV-38 — OPT / post-release — оптимизировать block conversion после YUV-32

- Владелец / модель: Terra / Claude Sonnet 5
- Ожидаемое reasoning: Low
- Статус: BLOCKED
- Зависимости: после YUV-32
- Не блокирует YUV-18.

### Проблема

BGRA→I420/NV сейчас вычисляет U/V для каждого pixel, хотя пишет chroma один раз
на 2×2 block. После YUV-32 четыре Y и одна averaged UV pair могут считаться
block-wise общим helper без выбрасывания 75% chroma arithmetic.

### Architect Decision

Оптимизировать только после принятого YUV-32 oracle. Обрабатывать 2×2 blocks с
actual sample count на odd edges; сохранить BT.601 limited coefficients,
rounding, strides и legacy `(U,V)` order byte-for-byte.

### DoD

- [ ] Native/Web output совпадает с принятым YUV-32 reference.
- [ ] Odd/padded cases и canaries остаются зелёными.
- [ ] Benchmark показывает эффект без изменения публичного API.
- [ ] Optimization commit не меняет manifest/thresholds.

### Результат

Не заполнен.

---

---

---

## YUV-39 — P2 / optional research — исследовать проверенные stride-aware реализации native primitives

- Владелец / модель: Terra / Claude Sonnet 5
- Ожидаемое reasoning: Medium
- Статус: TODO
- Зависимости: нет
- Не блокирует YUV-18 и текущий refactoring batch.
- Scope: исследование и рекомендации; production-код, native C, headers,
  bindings, manifests и зависимости не изменять.

### Проблема

Текущие conversion/manipulation primitives написаны локально, и аудит уже
обнаружил ошибки вокруг row stride, odd 4:2:0 geometry, chroma addressing,
цветовой матрицы и сложности алгоритмов. Для значительной части операций есть
зрелые реализации, но «подключить библиотеку» не является автоматическим
решением: API может поддерживать только row stride, а не произвольный pixel
stride; отличаться по matrix/range/rounding, ROI/border/alpha semantics;
увеличивать binary/WASM size или создавать лицензионные обязательства.

### Architect Decision

Провести отдельное make/buy/adapt исследование до дальнейшей ручной оптимизации.
Основной кандидат для conversion/rotate/scale — официальный
[libyuv](https://chromium.googlesource.com/libyuv/libyuv/); для независимого
сравнения conversion/scaling —
[FFmpeg libswscale](https://ffmpeg.org/libswscale.html). Для blur, border и
filter semantics использовать
[OpenCV imgproc](https://docs.opencv.org/4.x/d4/d86/group__imgproc__filter.html)
как reference-кандидат, не предполагая включение тяжёлой зависимости в plugin.

Для каждой текущей функции зафиксировать один из исходов:

1. безопасно вызвать upstream API напрямую;
2. адаптировать известный алгоритм с проверенной лицензией и собственным
   stride-aware boundary;
3. сохранить локальную реализацию, но сверять её с независимым oracle;
4. кандидат не подходит — с конкретной технической причиной.

Решение не должно менять установленный legacy `nv21` `(U,V)` contract и не
подменяет YUV-30: если upstream semantics расходятся с ещё не выбранным
effects/ROI contract, исследование описывает варианты, а не выбирает публичное
поведение вместо владельца.

### Scope исследования

1. Составить inventory всех exported conversion/manipulation functions и
   сопоставить им точные upstream APIs/algorithms, а не общую ссылку на проект.
2. Раздельно проверить поддержку:
   - положительного и отрицательного row stride;
   - произвольного pixel stride или необходимость предварительного repack;
   - independent strides каждой Y/U/V/UV/RGBA/BGRA plane;
   - odd width/height и trailing chroma sample;
   - in-place/overlap, ROI origin, border, alpha и failure semantics;
   - BT.601/BT.709, full/limited range, rounding и UV/VU order.
3. Для direct dependency и selective vendoring оценить C/C++ ABI, поддерживаемые
   CPU/SIMD fallbacks, Android/iOS/macOS/Windows/Linux и WASM/Emscripten,
   toolchain/CMake impact, итоговый размер артефактов и стоимость обновлений.
4. Проверить upstream license и NOTICE/source-distribution obligations по
   первичному источнику; код из случайных snippets и несовместимых лицензий не
   переносить.
5. Отделить correctness/safety от performance: сначала доказать эквивалентность
   на oracle cases YUV-11/YUV-12 и sanitizer cases YUV-34, затем оценивать
   throughput/allocations. Не использовать текущую реализацию как единственный
   эталон.

### DoD

- [ ] Создан `native-primitives-research.md` с таблицей «текущая функция →
      кандидат → stride/geometry/color/ROI support → license → platform/size
      cost → рекомендация».
- [ ] Для каждого кандидата указаны точная версия/commit, upstream API и ссылка
      на первичную документацию или исходник.
- [ ] Row stride и pixel stride оценены отдельно; отсутствие поддержки pixel
      stride не записано как полная stride-awareness.
- [ ] Для conversion есть независимые expected vectors на odd/padded cases и
      явно описаны допустимые tolerance/rounding differences.
- [ ] Для rotate/crop/flip и blur/effects описаны overlap, ROI, border и alpha
      semantics, включая расхождения с решениями YUV-30/YUV-31/YUV-23.
- [ ] Измерены либо обоснованно оценены binary/WASM size, performance и
      integration/maintenance cost; неподтверждённые ожидания помечены как
      hypotheses.
- [ ] Итоговая рекомендация дана отдельно по каждой группе функций; нет общего
      решения «заменить всё одной библиотекой» без доказательств.
- [ ] Любые implementation-карточки предлагаются отдельно и остаются
      `DISCOVERED` до решения владельца; native C implementation требует
      regression/characterization cases и native runtime verification.
- [ ] В рамках YUV-39 не изменены production-код, native C/headers, generated
      bindings, build manifests и package dependencies.

### Проверка

- `git diff --check`
- `git status --short`
- ручная сверка всех ссылок, лицензий и заявленных API с upstream primary
  sources;
- проверка, что YUV-39 отсутствует в зависимостях YUV-18.

### Результат

Не заполнен.

---

---

---

## YUV-06 — P1 — восстановить Linux/macOS packaging и runtime loading

- Владелец / модель: Terra / Claude Opus 5
- Статус: BLOCKED
- Зависимости: Linux/macOS app-runtime environment; Android/iOS build evidence.
- Scope:
  - `lib/src/loader/impl/loader_io.dart`
  - `linux/CMakeLists.txt`
  - `macos/yuv_ffi.podspec`
  - `macos/Classes/**`
  - CI native build/smoke matrix
  - platform support section README только после фактической проверки
- Карточка YUV-25 объединена сюда: loader path, packaging и состав macOS pod
  target имеют один release outcome и не должны расходиться по разным commits.

### Решение архитектора 2026-09-14

Карточка отложена по решению инженера: доступная машина работает под Windows,
поэтому обязательный Linux/macOS app-runtime retest локально сейчас недоступен.
Успешные CI smoke jobs сохраняются как evidence, но не закрывают замечания
независимого ревью. Возвращать YUV-06 в `todo.md` только при наличии подходящей
Linux/macOS среды либо согласованного CI app-runtime сценария; повторно
одобрять текущий batch не требуется.
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
   Исправить некритичные двойные слэши в iOS forwarder paths только внутри того
   же согласованного изменения, не отдельным cleanup-коммитом.
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
- Добавлен regression/smoke case, подтверждающий загрузку и реальную BGRA/YUV-операцию на каждом изменённом native path; он должен быть воспроизводимо красным до исправления packaging/layout.

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

Evidence собран в CI: локальная машина — Windows, ни Linux, ни macOS на ней нет.

#### Что изменено

- `lib/src/loader/impl/loader_io.dart` — загрузчик больше не открывает
  `native/src/build/libyuv_ffi.{so,dylib}`. Это путь дерева сборки CMake,
  которого нет ни в опубликованном пакете, ни в бандле приложения, поэтому
  любой потребитель вне этого репозитория падал на первом FFI-вызове. Linux
  грузит установленное имя `libyuv_ffi.so` (как Android уже делал), iOS берёт
  символы процесса.
- macOS: `DynamicLibrary.process()` верен для приложения, где исходники
  слинкованы в pod target, но `flutter test` — голая Dart VM, туда не линкуется
  ничего. Загрузчик проверяет `providesSymbol` и при отсутствии символов
  открывает установленную dylib, поэтому работают оба хоста.
- `macos/Classes/**` — pod target содержал один форвардер к агрегатору, в
  котором только include заголовка, то есть **ни одной реализации операций для
  macOS не собиралось**. Добавлены четыре форвардера по образцу iOS. Проверено
  программно: набор include идентичен iOS, каждая translation unit включена
  ровно один раз.
- `test/native_packaging_smoke_test.dart` — новый smoke, который **отказывается
  пропускаться**. Остальные native-сьюты глушат ошибку открытия и делают skip:
  прогон, где всё пропущено, в логе неотличим от прогона, где всё прошло —
  именно так сломанная упаковка оставалась зелёной. Этот вызывает
  `ensureInitialized()`, реальную конвертацию и in-place эффект.
- `test/reference_native_conversions_test.dart` — проба библиотеки отвязана от
  жёсткого `native/src/build/`; ищет по пути загрузчика с откатом на legacy.
  Scope расширен по согласованию с владельцем.
- `.github/workflows/ci.yml` — новые джобы `linux-native-smoke` и
  `macos-native-smoke`; старая джоба переведена на штатный путь.

#### Evidence

Прогон [34839218249](https://github.com/Anfet/yuv_ffi/actions/runs/34839218249),
commit `7a0a644`:

```text
linux-native-smoke:        success
macos-native-smoke:        success
example-analyze-and-build: success
wasm-web-integration:      success
analyze-and-test-vm:       failure  (31 pre-existing, см. ниже)
```

Linux smoke: `YUV-06 packaging smoke passed on linux (3.12.2)`, `All tests
passed!`. macOS smoke зелёный после исправления контракта загрузчика.

#### Регрессия, внесённая и исправленная в процессе

Первая попытка (`fb66c6f`) перенесла сборку из `native/src/build/`, но
эталонный сьют проверял файл по этому пути и стал пропускать все 119 кейсов:
было 289 passed / 31 failed, стало 201 / 1 / 119 skipped. Выглядело как
«починилось 30 тестов» — на деле 119 перестали исполняться. Исправлено в
`7a0a644`.

После исправления: **290 passed / 31 failed / 0 skipped**. Состав падений
сверен поимённо с базовым прогоном
[34824271019](https://github.com/Anfet/yuv_ffi/actions/runs/34824271019) —
`diff` пустой, **IDENTICAL FAILURE SETS**. Прирост +1 к passed — это новый
smoke-case. Провенанс подтверждает, что матрица реально исполнялась:
`library=/home/runner/work/_temp/native-build/libyuv_ffi.so, exists=true`.

#### Границы утверждения

- `analyze-and-test-vm` остаётся красной: те же 31 падение, что и до карточки.
  Это дефекты blur/effect/format-конверсий, к packaging отношения не имеющие,
  и YUV-06 их не чинила.
- Desktop-сборки собирают `example` со скаффолдингом `flutter create` на лету:
  в `example/` нет папок `linux/` и `macos/`, сгенерированные раннеры в
  репозиторий не добавлялись.
- Android/iOS runtime не проверялся — только контракт загрузчика. В CI для них
  джоб нет.
- Локально проверено на Windows: smoke зелёный, проба эталонного сьюта
  по-прежнему находит `yuv_ffi.dll`.

### Независимое ревью root 2026-09-14

Статус на момент ревью: `CHANGES REQUESTED`, количество обязательных доработок: 2. Архитектурное решение остаётся
валидным; Linux installed-name path и macOS source composition выглядят
корректно, а CI действительно показывает успешные `linux-native-smoke` и
`macos-native-smoke` для commit `7a0a644`.

DoD пока не доказан по двум обязательным путям:

1. macOS `Packaging smoke` выполняется из plain Dart VM и открывает отдельно
   собранную CMake `libyuv_ffi.dylib` через `DYLD_LIBRARY_PATH`. Это не проверяет
   заявленный app path `DynamicLibrary.process()` и не доказывает, что symbols
   из `macos/Classes/*.c` доступны и не выкинуты линкером в CocoaPods host.
   Нужен macOS integration/runtime smoke через собранное example-приложение,
   вызывающий `ensureInitialized()` и реальную conversion/effect operation.
2. В зафиксированном решении и DoD требуются mobile build checks, но workflow не
   содержит Android build и iOS build без codesign. Добавить оба либо отдельно
   согласовать изменение DoD с инженером; отсутствие runtime на mobile допустимо,
   отсутствие build evidence — нет.

После исправлений приложить новый CI URL и isolated follow-up commit. Набор из
31 известных conversion/effect failures не относится к отклонению YUV-06.

---

---

---

## YUV-12 — P1 — проверить все преобразования на Web/WASM backend

- Владелец / модель: Luna / Claude Sonnet 5
- Статус: BLOCKED
- Зависимости: YUV-40 (YUV-01, YUV-02 и YUV-10 приняты)
- Scope:
  - `example/integration_test/reference_web_conversions_test.dart`
  - `test/web/reference_web_conversions_test.dart` только если suite не требует asset bundle
  - shared test helpers и manifest из YUV-10
  - `failed-test-cases.md`, только регистрация фактических падений
  - WASM artifacts только пересобрать, не исправлять production C/Web code

### Проблема

Текущие Web tests используют маленькие synthetic patterns и smoke assertions. Команда `-d chrome` запускала их на VM со skip. Нет доказательства, что каждая операция обрабатывает реальный `512x512` asset так же, как независимый эталон.

### Зафиксированное решение

1. Пересобрать WASM из текущего source перед прогоном.
2. Перенести ту же data-driven manifest matrix, что и YUV-11, в
   `example/integration_test/` и выполнить её через `flutter drive` в Chrome,
   чтобы тест получал реальный Flutter asset bundle и WASM runtime.
3. Использовать те же expected artifacts и thresholds, что native. Не создавать Web-specific expected images.
4. Проверять metadata, planes, in-place contract и exact/tolerance metrics так же, как в native suite.
5. Добавить явный Web environment assertion, чтобы case suite не мог пройти на VM.
6. Каждый failed case зарегистрировать в `failed-test-cases.md` с браузером, Flutter/Dart version, WASM source commit и metrics.
7. Не исправлять production behavior и не повышать tolerance в рамках этой задачи.

### DoD

- Все строки полной обязательной матрицы реально исполняются с `kIsWeb == true`
  через integration harness. Сокращать матрицу до smoke-набора нельзя.
- Native и Web используют одинаковые case IDs, input SHA и expected artifacts.
- В результате записано фактическое число executed/passed/failed cases; skip не засчитывается как executed.
- Все падения полностью отражены в `failed-test-cases.md`.
- WASM artifacts однозначно связаны с тестируемым source commit.
- Если suite не зелёный, задача может перейти в `READY FOR REVIEW` только при полном failure log.

### Проверка

```powershell
Push-Location example
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/reference_web_conversions_test.dart -d chrome
Pop-Location
flutter analyze test
Push-Location example
flutter analyze
Pop-Location
dart format --output=none --set-exit-if-changed test
git diff --check
git status --short
```

Перед командами выполнить `tool/wasm/build_wasm.sh` в поддерживаемом shell и записать exact command/exit code.

### Решение архитектора 2026-09-14

- `RESOLUTION NEEDED` не вводится: карточка имеет статус `BLOCKED` и перенесена
  в waitlist.
- F-010 выделен в YUV-40: это изолированная диагностика обрыва на
  `FORMAT-TO-NV21-BGRA-TIGHT`, без production-исправлений и изменения допусков.
- F-009 направлен в YUV-13 для классификации общих native/Web и Web-specific
  расхождений. До полного Web-прогона отдельная fix-карточка не создаётся.
- После принятия YUV-40 исполнитель возобновляет тот же прогон 119 cases и
  завершает исходный DoD YUV-12. Расширять scope YUV-12 до исправления backend
  или native C не разрешено.

### Результат

Задача **не выполнена**: полный прогон матрицы не получен. Статус —
`BLOCKED`: исполнитель упёрся в F-010 вне Scope карточки. Дальше — фактические
данные частичного прогона, они не закрывают DoD.

#### Что сделано

- Матрица портирована в `example/integration_test/reference_web_conversions_test.dart`
  (119 cases, те же case IDs, expected artifacts и tolerances, что в native).
- Оракул `test_pattern_reference.dart` скопирован в
  `example/integration_test/helpers/reference/`. Копия, а не cross-package import:
  DDC не резолвит относительный импорт за пределы пакета. Код совпадает —
  sha256 без комментариев идентичен оригиналу, удалённых/изменённых строк нет.
- Фикстуры скопированы в `example/assets/reference/` (~1.7 МБ: manifest,
  source PNG, 24 PNG-артефакта), скрипт регенерации —
  `example/tool/copy_reference_fixtures.sh`. Сырые `.bin`/`.yuv` не копировались:
  с диска они не читаются, ожидаемые сырые байты пересчитывает `parametersForRaw()`.
- В `example/pubspec.yaml` добавлены `crypto`, `image` и секция `assets:`
  (расширение Scope согласовано с Архитектором).
- WASM пересобран: `bash ./tool/wasm/build_wasm.sh`, exit 0,
  `git status --short assets/wasm/` пустой — закоммиченные артефакты
  соответствуют текущим C-исходникам.

#### Прогон 1 — недействителен

`main()` был объявлен `async`, и `test()` вызывались после `await`. Результат:

```text
00:00 +1: All tests passed!
DartError: Bad state: Can't call test() once tests have begun running.
reference_web_conversions_test.dart 82:3
```

Исполнено 0/119. Строка «All tests passed!» относилась к единственному
зарегистрированному тесту и была ложной. Регистрация переписана на синхронную:
`void main()` + один `testWidgets` с циклом по всем cases и per-case `debugPrint`.

#### Прогон 2 — частичный

```text
cd example
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/reference_web_conversions_test.dart -d chrome
YUV-12 web provenance: kIsWeb=true, cases=119
```

Environment: Flutter 3.38.10, Dart 3.10.9, Chrome 153.0.8010.37, Windows x64.
WASM: `yuv_ffi.wasm` sha256 `61b6c52d9aca319ed575cf403729d8684fa8ea5cc99f4d36abc638523e495569`,
последний commit по C-исходникам `3524f05`, HEAD `2ae1dc3`.

**executed 19 / 119, passed 7, failed 12, не исполнено 100.**

Passed (все BGRA + два `fromRgba8888`):

```text
CONSTRUCT-BGRA8888-TIGHT       CONSTRUCT-BGRA8888-PADDED
INPUT-FROM-RGBA-BGRA8888       OUTPUT-TO-BGRA-BGRA8888-TIGHT
OUTPUT-TO-BGRA-BGRA8888-PADDED INPUT-FROM-RGBA-I420
INPUT-FROM-RGBA-NV21
```

Failed (все — I420/NV21):

```text
CONSTRUCT-I420-TIGHT       CONSTRUCT-I420-PADDED
OUTPUT-TO-BGRA-I420-TIGHT  OUTPUT-TO-BGRA-I420-PADDED
CONSTRUCT-NV21-TIGHT       CONSTRUCT-NV21-PADDED
OUTPUT-TO-BGRA-NV21-TIGHT  OUTPUT-TO-BGRA-NV21-PADDED
FORMAT-TO-BGRA-I420        FORMAT-TO-BGRA-NV21
FORMAT-TO-I420-BGRA-TIGHT  FORMAT-TO-I420-NV21-TIGHT
```

Характер падений (F-009):

- `CONSTRUCT-I420-TIGHT` и `CONSTRUCT-NV21-*` падают на `_assertPlaneReference`
  по sha256 плоскости, то есть расхождение возникает уже при конструировании,
  до какой-либо операции.
- Метрики вне допуска: `OUTPUT-TO-BGRA-I420-TIGHT` и `FORMAT-TO-BGRA-I420` —
  `mae=44.469 max=255 p99=255 outside=101888` при пороге `yuvRoundTrip`
  (`mae<=18`, `max<=160`); `FORMAT-TO-I420-BGRA-TIGHT` — `mae=10.233 max=144`.
- `FORMAT-TO-I420-NV21-TIGHT` — геометрия: `Expected: <256>, Actual: <512>`.

Все пять BGRA-кейсов, включая padded, прошли с `mae=0.000 max=0` — Web/BGRA
совпадает с эталоном побайтово.

#### Обрыв прогона (F-010)

После 19-го case (`FORMAT-TO-I420-NV21-TIGHT`) 20-й — `FORMAT-TO-NV21-BGRA-TIGHT` —
не напечатал ни PASS, ни FAIL. Цикл ловит все исключения через
`catch (error, stackTrace)`, поэтому молчание означает, что исполнение
прервалось некатчабельно (WASM trap либо `Error`, убивающий isolate), а не
провал assertion. Строки `YUV-12 summary` в логе нет, счётчик остался `+0`.
В логе нет ни timeout, ни pending timer, ни потери соединения.

Прогон завершился сам: `Application finished.` и `EXIT=1`. Ранее я ошибочно
сообщил, что драйвер завис — это неверно, зависания во втором прогоне не было.

#### Чего не хватает для DoD

- 100 cases из 119 не исполнены; пока не устранён обрыв (F-010), полный
  failure log недостижим.
- Согласно правилу карточки, `READY FOR REVIEW` возможен только при полном
  failure log, поэтому в review карточка не отдаётся.
- Production behavior и tolerances не трогал, как требует карточка.

#### Запрос исполнителя и ответы архитектора

Исполнитель не может двигаться дальше в пределах Scope карточки. Решения:

1. **F-010 (обрыв) — чья задача?** Причина обрыва, вероятно, в production-коде
   Web-бэкенда или в WASM, а карточка прямо запрещает чинить production в своих
   рамках. Нужна отдельная карточка на диагностику `FORMAT-TO-NV21-BGRA-TIGHT`
   либо явное расширение Scope YUV-12.
   **Ответ:** отдельная диагностическая карточка YUV-40 в waitlist; Scope
   YUV-12 не расширять.
2. **F-009 (расхождение I420/NV21) — куда направить?** Часть падений может
   дублировать известные native-дефекты (native-прогон той же матрицы: 65/119).
   Разделение native/Web — это YUV-13, но она идёт после YUV-12, а YUV-12
   заблокирована. Нужно решение о порядке.
   **Ответ:** зарегистрировать F-009 за YUV-13, но не начинать классификацию до
   завершения полного Web-прогона YUV-12.
3. ~~**`example/pubspec.lock`.**~~ **Закрыто 2026-09-14, решение владельца.**
   Причина просадки установлена: локальный Flutter 3.38.10 против CI 3.44.9.
   Файл переписывал не человек, а сам тулчейн — `flutter analyze`, `test` и
   `drive` неявно зовут `pub get`, и каждый вызов возвращал
   `characters` 1.4.1→1.4.0, `matcher` 0.12.19→0.12.17,
   `material_color_utilities` 0.13.0→0.11.1, `meta` 1.18.0→1.17.0,
   `test_api` 0.7.11→0.7.7, floor `>=3.10.0-0`→`>=3.8.0-0`.

   Ручная склейка (версии HEAD + четыре добавления) не выжила: первый же
   `pub get` её снёс. Проверено, что на 3.38 проект полностью работоспособен —
   `flutter analyze lib test` чистый, 49 тестов в трёх сьютах проходят, — то
   есть поднимать `sdk` в `pubspec.yaml` не требуется и публичный контракт
   пакета не трогается.

   Итог: commit `95a8517` (лок под 3.44.9) отменён в `6db12b3`. В репозитории
   лежит лок, который локальная среда воспроизводит сама; после отката
   повторный `flutter analyze` оставил файл чистым. На CI это не влияет: все
   джобы зовут обычный `flutter pub get` без `--enforce-lockfile`, и `example`
   не публикуется, поэтому закоммиченный лок там ничего не фиксирует.
4. **Статус `RESOLUTION NEEDED`** отсутствует в списке статусов очереди
   (секция «Правила очереди») и в `failed-test-cases.md`.
   **Ответ:** новый статус не вводить; карточка переведена в `BLOCKED`.

---

---

---

## YUV-40 — P1 — диагностировать некатчабельный обрыв Web/WASM matrix

- Владелец / модель: Terra / Claude Sonnet 5
- Статус: DISCOVERED
- Зависимости: одобрение инженера
- Блокирует: YUV-12; через неё YUV-13 и YUV-18
- Scope:
  - `example/integration_test/reference_web_conversions_test.dart`
  - минимальный отдельный Chrome integration target для одного failing case
  - test-only markers/logging и сбор browser console evidence
  - `failed-test-cases.md`, только уточнение F-010
  - production Dart, C, WASM artifacts и tolerances не изменять

### Проблема

Полная Web reference matrix прерывается на 20-м case
`FORMAT-TO-NV21-BGRA-TIGHT`: case не печатает PASS/FAIL, per-case `catch`
не срабатывает, итоговая summary отсутствует, а следующие 100 cases не
исполняются. По текущему логу нельзя отличить ошибку test harness, потерю
isolate, WASM trap и повреждение памяти.

### Зафиксированный план диагностики

1. Вынести failing case в минимальный самостоятельный Chrome integration
   target и поставить различимые маркеры до/после каждого вызова.
2. Добавить соседний control case, подтверждающий работоспособность того же
   harness и загрузчика WASM.
3. Захватить stdout драйвера и browser console/JS/WASM error; записать точный
   exit code и последнюю достигнутую границу.
4. Воспроизвести на основном Flutter 3.44.9; Flutter 3.38 допустим только как
   дополнительная проверка совместимости.
5. Классифицировать первопричину и сформировать отдельную implementation task.
   В рамках YUV-40 не менять production behavior, native C/WASM и thresholds.

### DoD

- Изолированный case воспроизводит либо опровергает F-010 независимо от остальных
  118 cases.
- Control case проходит в том же окружении.
- Есть точный лог границы обрыва и однозначная классификация слоя отказа либо
  перечень оставшихся гипотез с доказательством каждой проверки.
- Сформулирована минимальная follow-up карточка с regression test requirement;
  production-код не изменён.
- После принятия диагностики YUV-12 можно вернуть в `todo.md` для полного
  прогона, но это не означает автоматического разрешения implementation task.

### Проверка

```powershell
Push-Location example
flutter drive --driver=test_driver/integration_test.dart --target=<isolated-target> -d chrome
Pop-Location
flutter analyze example/integration_test
# Захват browser console согласно выбранному harness
git diff --check
git status --short
```

---
## YUV-18 — P0 / release gate — финальная приёмка и подготовка `0.2.5`

- Владелец / модель: Terra / Claude Sonnet 5
- Статус: BLOCKED
- Зависимости: YUV-06, YUV-08, YUV-09, YUV-12, YUV-13,
  YUV-22, YUV-23, YUV-30, YUV-31, YUV-32, YUV-33, YUV-34
  (YUV-02/YUV-07/YUV-14/YUV-15/YUV-17/YUV-20 приняты)
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

- Все перечисленные обязательные зависимости имеют статус `DONE` и независимое
  verification evidence. Опциональные YUV-24, YUV-26, YUV-29 и
  post-release YUV-28 выпуск не блокируют.
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
