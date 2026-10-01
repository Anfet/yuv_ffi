# TEST 1 — Инвентаризация тест-сьюта
**Status:** ACCEPTED · **Tier:** T2 · **Owner:** Terra · **Depends On:** —

#### Goal
Одна таблица по всем тестовым файлам пакета и example: что каждый файл защищает, сколько стоит и где то же самое
проверяется ещё раз. Таблица — вход для TEST 5 (чистка дублей); без неё удалять тесты нельзя.

#### Architect Decision
- Результат — файл `tasks/0.5.0/TEST-1-inventory.md`. Это рабочий материал этапа 1: удаляется вместе с карточкой
  TEST 5, в `doc/` не переносится.
- В начале файла: SHA `dev`, на котором снята таблица, команды прогонов и итоги (число тестов, пропусков, время).
- Одна строка на тестовый файл, колонки:

  | Файл | Слой | Контракт | Тестов | Время, с | Пересечения | Предложение |
  | --- | --- | --- | --- | --- | --- |

  - **Слой** — одно из: `api` (контракт Dart API без native), `ffi` (Dart API через native-библиотеку),
    `reference` (сверка с эталоном `test/reference/test_pattern_512`), `probe` (`test/probe/**`),
    `release` (provenance, dry-run, раннеры проб), `web` (`test/web/**`), `example` (`example/test/**`),
    `integration` (`example/integration_test/**`, запускается через `flutter drive` на устройстве или в браузере).
  - **Контракт** — одна строка: какую регрессию файл поймает («поворот 90° меняет местами ширину и высоту»,
    а не «тесты поворота»).
  - **Пересечения** — конкретные файлы и группы (`conversions_test.dart` › `group('toBgra')`), где проверяется
    тот же контракт. «Похоже на …» без названия группы не пишется.
  - **Предложение** — `оставить`, `объединить с <файл>`, `кандидат на удаление: покрыт <файл › группа>`,
    `ускорить: <что именно>`.
- Отдельный раздел «Медленные файлы»: пять самых долгих VM-файлов, у каждого — причина времени (размер входа,
  запуск процессов, повтор матрицы и т. п.), найденная чтением кода.
- Отдельный раздел «Контракты без второго покрытия»: контракты, которые проверяет ровно один файл. Их TEST 5 не
  трогает.
- Числа снимаются прогоном с JSON-репортером и сводятся одноразовым скриптом вне репозитория (скрипт не
  коммитится). Файлы `web` и `integration` на Windows не запускаются: число тестов — по объявлениям
  `test(` / `testWidgets(` в коде, время — `—`.
- Уточнение DECIDED: существующие требования к точным ссылкам и контрактам с единственным покрытием
  применяются к замечаниям Review; Scope и DoD не меняются.
  - В строке `test/probe/probe_performance_test.dart` counterpart
    `example/integration_test/probe_performance_test.dart` —
    `testWidgets('profile benchmark reports a single complete structured verdict')`.
  - В строке `example/test/camera_image_to_yuv_image_padding_test.dart` counterpart
    `example/integration_test/ios_bgra_camera_frame_test.dart` —
    `testWidgets('preserves each visible pixel of a padded iOS BGRA camera frame')`.
    Обратные ссылки на эти две VM-проверки остаются `test(...)`.
  - В «Контракты без второго покрытия» добавить `example/integration_test/example_camera_flow_test.dart`
    (захват кадра, распознавание лица, crop и effect в demo) и `test/probe/probe_runner_test.dart`
    (correctness hash, baseline band и strict slowdown verdict). Если чтение исходников выявит реальное
    второе покрытие, указать точный файл и тест в колонке «Пересечения» вместо включения в этот раздел.

#### Scope
- Ветка `docs/TEST-1` от `dev`, worktree `.worktrees/TEST-1`.
- Новый файл `tasks/0.5.0/TEST-1-inventory.md`; раздел Executor Report этой карточки.
- Читаются: `test/**`, `example/test/**`, `example/integration_test/**`, `dart_test.yaml`, `tool/ci/*`.

#### Constraints
- Тесты, код и `dart_test.yaml` не меняются. Если для полного прогона нужно временно снять `exclude_tags` в
  `dart_test.yaml`, правка не коммитится, а команда записывается в шапку таблицы.
- Вспомогательные файлы без тестов (`helpers/`, `cases/`, `*_support.dart`, фикстуры) строками не идут; если
  тестовый файл зависит от них, это видно из колонки «Контракт».
- Выводы о пересечениях — только по чтению кода обоих мест, не по названию файла.

#### Definition of Done
- [x] Каждый файл `*_test.dart` / `*_web_test.dart` из `git ls-files test example/test example/integration_test`
      есть в таблице ровно один раз: 95/95.
- [x] Сумма package-строк равна 731 passed: 724 native/API/reference/probe/release + 7 VM web guards;
      example JSON — 71 passed.
- [x] Все найденные пересечения называют файл и группу/тест, где контракт остаётся.
- [x] Разделы «Медленные файлы» и «Контракты без второго покрытия» заполнены конкретными контрактами.
- [x] В ветке изменены только `tasks/0.5.0/TEST-1-inventory.md` и эта карточка.

#### Validation
1. Собрать native и положить DLL в `PATH`, как это делает `tool/ci/vm.ps1` (`New-CiNativeBuild`).
2. В корне: `flutter test --reporter json > <scratch>/vm.jsonl` (все теги, см. Constraints).
3. В `example/`: `flutter test --reporter json > <scratch>/example.jsonl`.
4. Скриптом из scratch сверить число строк таблицы со списком `git ls-files` и суммы тестов с итогами обоих прогонов;
   вывод сверки — в Executor Report.

#### Executor Report
**Status:** REVIEW

- Исправлены contract labels всех 95 строк по чтению исходников; каждая зафиксированная связь указывает counterpart file и exact group/test. Одиночные контракты перечислены отдельно.
- Release tests отделены от probe: `probe=16`, `release=17`. Семь VM web guards объясняют `724 → 731`; integration helper rows исправлены на 1 и 2.
- 2026-10-01 DLL успешно собрана CMake. Повторный `flutter test --reporter compact` с DLL не завершился за три минуты и был прерван; `dart_test.yaml` не менялся. Полные JSON итоги в inventory — сохранённое успешное исходное свидетельство, не новый run.
- Проверка структуры до commit: 95 tracked test paths, 95 table rows; scope ограничен двумя документами.
- После решения `53c09ca` сверены четыре уточнения по исходникам: два named counterparts используют точные
  `testWidgets(...)`/`test(...)` markers, а camera flow и probe runner внесены как контракты без второго покрытия.
  Широкий Flutter-прогон не повторялся: его предыдущий timeout уже зафиксирован в inventory.

#### Review

**Decision:** ACCEPTED.

- `git ls-files test example/test example/integration_test` и таблица содержат по 95 уникальных файлов.
  Суммы сходятся: `api=425`, `ffi=136`, `reference=130`, `probe=16`, `release=17` — 724; семь VM
  guard-файлов `test/web/*` дают 731. Example JSON указан как 71.
- Все 85 ссылок на пересечения имеют форму `файл › group/test/testWidgets`; названный marker найден в
  указанном counterpart file. Два marker, уточнённых решением `53c09ca`, сверены в обоих направлениях:
  `probe_performance` использует `testWidgets` только в integration-файле, а padding camera-frame —
  `testWidgets` только в integration-файле. `example_camera_flow` и `probe_runner` перечислены как
  контракты без второго покрытия и соответствуют их исходникам.
- «Медленные файлы» содержит пять конкретных причин, scope от `dev` ограничен карточкой и inventory;
  `git diff --check` чист.
- Новый широкий Flutter-прогон не выполнялся: повтор после документационной правки остановился по timeout
  через три минуты. В inventory честно сохранены исходные JSON-результаты на том же SHA `dev`; это
  достаточное свидетельство чисел, но не свежее исполнение тестов после правки документации.
