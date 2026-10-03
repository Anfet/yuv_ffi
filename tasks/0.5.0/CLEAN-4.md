# CLEAN 4 — Документация и комментарии по стандартам pub.dev
**Status:** ACCEPTED · **Tier:** T2 · **Owner:** Executor (T2) · **Depends On:** — · **Probe:** windows

#### Goal
Привести публикуемый пакет к обычному виду пакета pub.dev: README, CHANGELOG, `example/README.md`, dartdoc
публичного API и комментарии в коде (`lib/`, `src/`, `darwin/`, `example/lib/`) — без внутреннего шума. Что уже
видно при постановке:

- в комментариях кода остались внутренние ID задач (`PACK-01D`, `RA-25` и т. п., около 10 мест) и рассуждения
  о процессе — им место в git, не в коде;
- комментарии, пересказывающие следующую строку, и длинные «истории» вместо причины;
- dartdoc публичного API не проверяется: нет `public_member_api_docs`, `dart doc` не прогоняется;
- `.pubignore` перечисляет давно удалённые файлы; `doc/archive/` закоммичен (9 файлов), хотя история — в git
  (`AGENTS.md`, «История задач»);
- оценка `pana` и `dart pub publish --dry-run` не снимались.

Эталон проверки — `pana` (оценка и замечания), `dart pub publish --dry-run` без предупреждений, `dart doc` без
предупреждений. Поведение кода не меняется; `lib/src/functions/bindings/` (сгенерированный) не трогать.

Этап 6, пул `CLEAN4` в ветке `all/CLEAN-4` от `dev` (после слияния CLEAN 3, CI 2, CI 3).

Замеры Architect на `045d761` (03.10.2026):

- `flutter pub publish --dry-run` — 0 предупреждений, 1 подсказка (предыдущая опубликованная версия — 0.2.4, скачок
  версии). Архив 1018 КБ; в него попадают `test/` (12 МБ до сжатия, эталоны и пробы), `test_native/`, `tool/`,
  корневой `CMakeLists.txt` (только native-тесты), `ffigen.yaml` и `doc/*.md` — внутренние документы на русском.
- `public_member_api_docs` на `lib/` — 29 замечаний в 9 файлах: экспортируемые `yuv_frame_renderer.dart`,
  `yuv_frame_geometry.dart`, `yuv_codec.dart`, `impl/io/yuv_image.dart` и внутренние `web/impl/js_util_compat_web.dart`,
  `impl/yuv_stub.dart`, `impl/web/yuv_web.dart`, `loader/impl/wasm_loader_*.dart`.
- Внутренние ID в коде: `lib/src/widgets/yuv_frame_renderer.dart` (WEB 1), `example/lib/device_check/*` (DEVICE-1),
  `example/test/yuv_image_to_input_image_test.dart`, `test/pack_planes_native_equivalence_test.dart`,
  `test/yuv_pack_test.dart`, `test/yuv_plane_layout_test.dart`, `test/yuv_plane_validation_test.dart`,
  `test/reference_native_conversions_test.dart` (PACK-xx); `example/README.md` (DEVICE-2). В `src/`, `darwin/`,
  README и CHANGELOG — нет.
- Опечатка в tooltip «Rotate Couterclockwise» (`example/lib/editor/editor_screen.dart`); тесты на этот текст не
  ссылаются.
- `pana` на этой машине не установлен.

#### Architect Decision
1. **Правило комментария** (глобальный `CODESTYLE.md` и `CLAUDE.md`, «Comments in widget code»):
   - остаётся — причина: почему значение такое, что сломается без строки, что пробовали и отвергли; ограничения
     платформы и движка;
   - уходит — ID задач и решений (`WEB 1`, `PACK-01B`, `D-17`), история («раньше было…», «перенесено в…»), пересказ
     следующей строки, закомментированный код;
   - ID заменяется сутью: «WEB 1: CanvasKit differs…» → «CanvasKit differs from the CPU reference by up to 255 in
     every shader-probe case, so Web uses the BGRA path.»
   Проход — по `lib/` (кроме `lib/src/functions/bindings/`), `darwin/`, `example/lib/`; в `test/` и `example/test/` —
   только ID из комментариев. `src/` — только если в нём найдутся ID или история (на `045d761` их нет); правится
   лишь текст комментариев.
2. **Dartdoc и `public_member_api_docs`.** Включить правило в `analysis_options.yaml` пакета (`linter: rules:`).
   Символы, экспортируемые через `lib/yuv_ffi.dart` и `lib/yuv_ffi_web.dart`, получают настоящий dartdoc: что это и
   как пользоваться, первая фраза — одно предложение. Внутренние файлы, которые наружу не экспортируются
   (`lib/src/**/impl/**`, `js_util_compat_web.dart`, `yuv_stub.dart`), — `// ignore_for_file: public_member_api_docs`
   первой строкой после заголовка, без выдуманных комментариев. В `example/` правило не включать.
3. **Документы пакета** (английский, D-7):
   - `README.md`: разделы прежние; сверить с кодом после CI 3 — каждый пример кода на текущем API, минимальная
     версия Flutter — как в `pubspec.yaml`, «Platform status» и «Web backend» — шейдер на Web выключен (WEB 1),
     Web — частичный WASM backend; «Building from source» — явно «from a repository checkout» (`tool/` и `ffigen.yaml`
     в архив не попадают, решение 4); без внутренних ID и заметок о процессе;
   - `CHANGELOG.md`: верхняя запись `0.5.0-dev.1` — только изменения для пользователя, без ID; номер версии не
     менять (переименование в `0.5.0` — этап 8);
   - `example/README.md`: «for the DEVICE-2 review» → «for the release review»; описание экрана — по коду CLEAN 3.
4. **`.pubignore`.** Пока он есть, pub не читает корневой `.gitignore`, поэтому файл — полный список. Переписать:
   - убрать строки давно удалённых файлов (`/Agent Orchestration Protocol.md`, `/dart-architecture-audit.md`,
     `/failed-test-cases.md`, `/web-gate-blocker.md`, `/todo-waitlist.md`, `/pre-release-todo.md`, `/completed.md`,
     `/scratch_rt_check/`, `/native-primitives-research.md`, `/test/tmp_verify/`, `/tool/migration/`,
     `/doc/perf/archive/` и т. п. — всё, чего нет в `git ls-files`), сохранив служебные шаблоны (`build/`,
     `.dart_tool/`, IDE, `*.log`, `yuv_ffi.dll`, `/.worktrees/`, `/pubspec.lock`);
   - исключить из архива разработческое: `/test/`, `/test_native/`, `/tool/`, `/doc/`, корневой `/CMakeLists.txt`,
     `/ffigen.yaml`, `/dart_test.yaml`, `/AGENTS.md`, `/todo.md`, `/COMPLETION.md`, `/tasks/`;
   - `example/` остаётся целиком (витрина на pub.dev).
   Корневой `CMakeLists.txt` плагинные сборки не используют: `linux/` и `windows/` подключают `../src` напрямую,
   Android и Darwin — свои файлы. Проверка — сборки решения 6.
5. **`doc/archive/`** — удалить (9 файлов, `release-0.4.2/ra26-windows-release`). Если в его `README.md` есть вывод,
   которого нет в `doc/perf-findings.md`, — одна строка туда со ссылкой `git show <sha>:<путь>`. Из
   `analysis_options.yaml` убрать исключение `doc/archive/**`.
6. **`pana`.** `dart pub global activate pana`, затем из корня `pana --flutter-sdk <путь к Flutter 3.44.9> .`. Каждый
   снятый балл либо исправлен (в Scope), либо объяснён в отчёте (например, платформа или WASM-совместимость, которые
   правятся в этапе 7). Метаданные `pubspec.yaml` (`topics`, `description`) — менять, только если `pana` снимает за
   них баллы; `version`, зависимости и `environment` — нет.
7. **Мелочь из CLEAN 3:** tooltip «Rotate Couterclockwise» → «Rotate Counterclockwise».
8. **Probe `windows`, а не `windows+pixel3`.** В `lib/src/yuv/impl/**` и `src/` меняются только комментарии и
   директивы `ignore_for_file` — машинный код не меняется. Reviewer проверяет это по diff; если в этих путях
   изменилось что-то кроме комментариев, карточка возвращается.
9. **Dart 3.12 (минимум по D-24).** Код под новый язык — только то, что подсказывает анализатор, без массовой
   модернизации:
   - `prefer_initializing_formals` — 2 места в `test/yuv_image_widget_test.dart` (private named parameters, Dart 3.12):
     `dart fix --apply --code=prefer_initializing_formals`;
   - `library_annotations` — 58 тестов с `@Tags` перед импортами без `library;`: добавить `library;` после аннотации;
   - primary constructors не использовать: в 3.12 экспериментальные, стабильны с 3.13 — выше минимума;
   - dot shorthands (Dart 3.10) — не мигрировать массово, только в строках, которые и так правятся.
   После этого `flutter analyze` в корне и в `example/` — «No issues found» (с infos).

#### Scope
- Комментарии и dartdoc: `lib/` (кроме `lib/src/functions/bindings/`), `darwin/`, `example/lib/`; ID в комментариях
  `test/`, `example/test/`; `src/` — только текст комментариев, если найдутся ID или история.
- `README.md`, `CHANGELOG.md`, `example/README.md`, `analysis_options.yaml`, `.pubignore`, `doc/archive/` (удаление),
  `doc/perf-findings.md` (при необходимости, решение 5).
- `example/lib/editor/editor_screen.dart` — tooltip (решение 7).
- `pubspec.yaml` — только метаданные по решению 6.
- `test/**` — директивы `library;` и 2 initializing formals по решению 9.

#### Constraints
- Поведение не меняется: ни строки исполняемого кода, кроме текста tooltip.
- `lib/src/functions/bindings/` и другие сгенерированные файлы не трогать.
- `example/lib/device_check/`: JSON отчёта (`'card': 'DEVICE-1'`) и маркеры лога `DEVICE-1 …` не менять — по ним
  читают результат проверки на устройстве в этапе 8; меняются только dartdoc и комментарии.
- Строки `RA-25` / `RA-26` внутри `expect` в `test/probe/*` — проверка содержимого скриптов `tool/`, не трогать.
- Версию пакета и запись `CHANGELOG.md` не переименовывать.

#### Definition of Done
- [ ] В `lib/`, `src/`, `darwin/`, `example/lib/`, `test/`, `example/test/` нет внутренних ID в комментариях
      (кроме ограничений выше): `git grep -nE '\b(PACK|RA|TEST|GEOM|VIEW|SHADER|CAMERA|CLEAN|WEB|CI|SPM|DEVICE|PERF|APPLE|D)[- ][0-9]+'`
      — вывод с объяснением оставшихся строк в отчёте.
- [ ] `public_member_api_docs` включено; `flutter analyze` в корне и в `example/` — «No issues found», включая infos
      (решение 9).
- [ ] `dart doc` в корне — 0 предупреждений (вывод — в `doc/api/`, он в `.gitignore`).
- [ ] `flutter pub publish --dry-run` — 0 предупреждений; в архиве нет `test/`, `test_native/`, `tool/`, `doc/`,
      внутренних `.md`; размер архива — в отчёте. Подсказка о скачке версии с 0.2.4 допустима.
- [ ] `pana` — оценка и каждое снятие баллов с решением в отчёте.
- [ ] `doc/archive/` удалён; `.pubignore` без строк удалённых файлов.
- [ ] README, CHANGELOG, `example/README.md` по решению 3.

#### Validation
Ключи: `lib/*` → `vm example`, `lib/src/yuv/impl/web/*` → `web`, `example/*` → `example`, `.pubignore` и
`analysis_options.yaml` → `all`/`vm`; ветка `all/CLEAN-3` их покрывает.

- `dart format --line-length 150` для изменённых Dart-файлов.
- `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/example.ps1`, `pwsh -File tool/ci/web.ps1`.
- Probe `windows` — `pwsh -File tool/ci/windows.ps1`.
- `flutter pub publish --dry-run`, `dart doc`, `pana` — по DoD.

#### Executor Report

Выполнено:

- Публичные README и example README приведены к текущему API/Flutter 3.44; Web описан как частичный WASM backend, а сборка из исходников явно требует checkout репозитория.
- Включено `public_member_api_docs`; добавлены dartdoc экспортируемым библиотекам, Web registration entrypoint и публичным геометрическим/кодековым типам. Внутренние `impl`-файлы получили точечный `ignore_for_file`.
- Убраны ID и история из комментариев; оставшиеся совпадения поиска — разрешённые JSON/log marker `DEVICE-1` и `expect`-строки RA-25/RA-26 в `test/probe/`.
- Удалён `doc/archive/`; `.pubignore` исключает тесты, native-тесты, tool, doc, CMake/ffigen и внутренние документы. Tooltip исправлен на `Rotate Counterclockwise`.
- Для Dart 3.12 добавлены `library;` после `@Tags`, применён `prefer_initializing_formals`; форматирование выполнено с line length 150.

Проверки:

- `flutter analyze` в корне и `example/` — PASS, `No issues found`.
- `pwsh -File tool/ci/vm.ps1` — PASS, 616/616, exit 0.
- `pwsh -File tool/ci/example.ps1` — PASS, exit 0.
- `pwsh -File tool/ci/web.ps1` — PASS, Chrome 154.0.8037.98, 14 source files, 63 integration cases, 119 reference cases, camera smoke; exit 0.
- `pwsh -File tool/ci/windows.ps1` — PASS, включая `shader_probe_native_test.dart`; exit 0.
- `dart pub publish --dry-run` — PASS, 0 warnings, 1 допустимая hint о предыдущей версии 0.2.4, архив 673 KB; exit 0.
- Linux/Flutter 3.44.9: `pana --flutter-sdk ... .` — PASS, 160/160, 152/152 public API documented; `CLEAN4_LINUX_PANA_EXIT=0`. Встроенный pana dartdoc завершился с 0 warnings/0 errors.
- Локальный `dart doc` из Flutter 3.44.9 использует dartdoc 9.0.4 и падает внутри `_stripDocImports` с известным RangeError ([dart-lang/dartdoc#4180](https://github.com/dart-lang/dartdoc/issues/4180)); это не ошибка пакета. Актуальный dartdoc 9.0.9 и dartdoc в Linux pana сгенерировали документацию без предупреждений.

Коммиты исполнения: `5f10d4c`, `a55d860`.
#### Review

- **ACCEPT** (Reviewer, 03.10.2026, `5f10d4c`, `a55d860`). Проверено Reviewer: `flutter analyze` в корне и в `example/`
  — «No issues found»; `flutter pub publish --dry-run` — 0 предупреждений, 1 подсказка о версии, архив 673 КБ, в нём только
  `lib/`, `src/`, платформенные каталоги, `assets/`, `shaders/`, `example/` и пакетные документы; в `lib/src/yuv/impl/**`
  — только директивы `ignore_for_file`, `src/` не тронут — Probe `windows` достаточен. `pana` 160/160 (Linux).
  `dart doc` локально падает в dartdoc 9.0.4 из Flutter 3.44.9 (dart-lang/dartdoc#4180), dartdoc 9.0.9 и pana — без
  предупреждений: принято. Поправлено Reviewer: решение 5 — вывод удалённого `doc/archive/` (PROBE 1, 0.4.0 против
  `dev`) дописан строкой в `doc/perf-findings.md`; в `yuv_web.dart` две директивы `ignore_for_file` слиты в одну.
  Комментарии с «legacy nv21» и «previously» в `lib/` описывают контракт API, а не историю — оставлены.
