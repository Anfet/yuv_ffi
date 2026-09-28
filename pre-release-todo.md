# yuv_ffi 0.4.2 — предрелизный цикл RA

Источник: предрелизный аудит 27.09.2026 (HEAD `9b41cb5`), повторная сверка 28.09.2026 на `db42681`. Карточки RA заменяют PRE-00…07 из `doc/archive/perf/prerelease-todo.md`. Архитектор — Claude Opus (T1). Engineer разрешил довести весь цикл до RA-50 по зависимостям; отдельный pub.dev publish не входит в задачу.

**Объём релиза заморожен.** VIEW-00…03 и PACK-00…01D приняты. С начала цикла RA в `lib/`, `src/`, `example/lib/` не добавляется новая функциональность; любое новое требование — отдельной карточкой после решения Engineer.

## CI и раннеры

- Правило Engineer: на GitHub-hosted — только одна Linux-джоба (`linux-native-smoke` + sanitizer). Остальное — self-hosted: `dev.working` (Windows x64: VM-матрица, Windows native, Android-эмулятор, Web/WASM, example) и `yuv-self-hosted` (macOS x64: macOS, iOS Simulator, bindings). WSL/Hyper-V не включать.
- На Windows-раннере: Android SDK `D:\.important\android-sdk`, AVD `Tablet` (API 35 x86_64), Chrome 154.0.8037.58 + ChromeDriver `D:\.projects\.tools\chromedriver-win64\chromedriver.exe`, Git Bash `D:\.important\Git\bin\bash.exe`, emsdk 3.1.74 в `D:\.projects\.tools\emsdk-3.1.74` (глобальный 5.0.1 не использовать).
- `tool/bench/` в рабочей копии принадлежит Engineer: не трогать и не коммитить.

## Состояние

Текущий `origin/release/0.4.2` — `2ef5e15`. RA-51 принята на ветке `ra/RA-51`: CI run `36471185052` зелёный на SHA `ea54e0c`; ожидает merge и CI на общем release SHA. RA-22 и RA-40 начнутся после интеграции; актуальные состояния оставшихся карточек и следующие шаги — в дашборде ниже.

## Решения Engineer

| ID | Status | Вопрос | Рекомендация Architect |
| --- | --- | --- | --- |
| D-1 | DECIDED 28.09.2026 | Версия релиза при смене умолчания layout (PACK-01B). | **0.4.2.** Последняя опубликованная неотозванная версия — 0.2.4, 0.4.0 отозвана, поэтому 0.5.0 ничего не даёт. Смена умолчания описывается как **Behavior change** в CHANGELOG и отдельной строкой в таблице миграции с 0.2.4 в README: фабрики с `planes:` теперь упаковывают плоскости, для старого поведения — `layout: YuvPlaneLayout.preserve`. |
| D-2 | DECIDED 28.09.2026 | Раннеры | GitHub-hosted — только одна Linux-джоба (правило Engineer). Число self-hosted раннеров увеличивается: RA-80. |
| D-3 | DECIDED 28.09.2026 | Очерёдность RA-25/26 | После слияния RA-51 перенести готовые локальные изменения в отдельные карточные ветки и заморозить RA-25/26 до фазы 6. До этого не запускать новые Pixel- или benchmark-прогоны. |

Отчёты исполнителей и ревью по карточкам цикла — в [архиве](doc/archive/release-0.4.2/ra-reports.md).

## Статусы

Базовые статусы протокола: `TODO`, `IN_PROGRESS`, `BLOCKED`, `ARCHITECT_REQUIRED`, `REVIEW`, `DONE`. По просьбе Engineer оркестратор уточняет их подстатусами, чтобы было видно, где задача сейчас. Каждый подстатус однозначно сводится к базовому и называет, кто делает следующий шаг:

| Подстатус | Базовый | Следующий шаг |
| --- | --- | --- |
| `REWORK`, `REWORK_VALIDATION_PENDING` | TODO | исполнитель: исправление и проверки |
| `REWORK_T1_REVIEW_PENDING`, `REVIEW_AT_END` | REVIEW | ревьюер (T1) |
| `LOCAL_FIXES_CI_PENDING` | IN_PROGRESS | исполнитель: коммит и CI-прогон |
| `CI_FAILED`, `CI_NOT_REACHED` | BLOCKED | исполнитель CI-карточки или владелец блокера |
| `CI_PASS_PENDING_NEGATIVE_CONTROL` | IN_PROGRESS | исполнитель: негативный контроль |

Новый подстатус добавляется в эту таблицу одновременно с первым использованием. Принятая карточка (`DONE`) сразу уходит из дашборда: краткая запись — в `COMPLETION.md`, файл карточки — `git mv` в `doc/archive/release-0.4.2/cards/` (карточки, принятые до 28.09.2026, — в `doc/archive/release-0.4.2/ra-accepted-cards.md`).

## Порядок цикла (Engineer, 28.09.2026)

| Фаза | Содержание | Карточки | Состояние |
| --- | --- | --- | --- |
| 1 | Чистка лишнего и документация | RA-01…06, RA-08, RA-10…17 | **завершена** |
| 2 | Тесты на Mac (параллельно с фазой 3): macOS native, iOS Simulator | RA-22 (только Mac-джобы) | Mac-джобы зелёные в run `36455663081`; осталось принять |
| 3 | Web | RA-40, RA-41 | RA-51 принята; RA-40 стартует на общем SHA, RA-41 зависит от RA-22 и RA-40 |
| **M1** | **Стабильный предрелиз:** фазы 1–3 закрыты, CI зелёный на одном SHA | — | — |
| 4 | Декомпозиция тест-сьюта: запускать только нужное | RA-60…RA-62 | TODO |
| 5 | Разделение CI: одна платформа — один workflow — одна карточка | RA-70…RA-78, RA-80 | TODO |
| 6 | Устройство и скорость | RA-25, RA-26, RA-27 | после фазы 5 |
| 7 | Релиз | RA-19, RA-18, RA-50 | последней |

Карточки фаз 4–7 не запускаются до M1. RA-25/RA-26 продолжаются только в той части, которая уже в работе; новые прогоны на устройстве — после фазы 5, когда CI перестанет требовать полного прогона на каждый push.

## Правила работы (Engineer, 28.09.2026)

1. **Одна карточка — одна ветка.** Исполнитель работает в ветке `ra/RA-xx` от `release/0.4.2`; при параллельной работе — в отдельном worktree `D:\.projects\yuv_ffi-wt\RA-xx`. В коммит попадают только файлы своей карточки. CI и ревью проверяют SHA ветки карточки. После приёмки оркестратор вливает ветку в `release/0.4.2`; M1 и RA-50 фиксируются только на SHA `release/0.4.2`. Общая рабочая копия `D:\.projects\yuv_ffi` — не место для незакоммиченной работы карточек.
2. **Локальная проверка до push и лимит CI-итераций.** Перед каждым push исполнитель выполняет локально проверки из Validation карточки (после RA-70 — `tool/ci/<name>`). Два красных прогона по одной причине, которую не удалось воспроизвести локально, — карточка переходит в `ARCHITECT_REQUIRED`, третьей попытки нет.
3. **Карточка — отдельный файл** `tasks/release-0.4.2/RA-xx.md`. Этот файл содержит только правила, порядок и дашборд. Дашборд и статусы правит только оркестратор; при расхождении статус дашборда главнее. Карточку правят архитектор (решение, DoD) и исполнитель (раздел `#### Executor Report` в конце). Исполнитель читает свою карточку и этот файл, остальные — по ссылке из Depends On.
4. **Решение `ARCHITECT_REQUIRED`.** Оркестратор вызывает Sol с reasoning medium для решения; карточка не останавливает фазу: остальные карточки продолжаются, вопросы собираются в общий список. Разбор с архитектором и Engineer — одной сессией на границе фазы или раз в день.
5. **Строгость ревью по риску.** Независимое ревью каждой карточки — для контракта API, native, проб и golden, CI-логики и релизных скриптов. Документация, чистка, перенос в архив и правки только комментариев принимаются одним пакетным ревью на фазу.
6. **Одна фаза за раз.** До M1 новые карточки создаются только для того, что блокирует M1; прочие идеи — одной строкой в раздел «Позже» `todo.md`. Исключение: фазы 2 (Mac) и 3 (Web) идут параллельно — разные раннеры и разный код.

## Дашборд

Порядок — по фазам цикла; ID ведёт к файлу карточки; Summary — текущее состояние и следующий шаг.

| Done | ID | Status | Tier | Owner | Depends On | Summary |
| --- | --- | --- | --- | --- | --- | --- |
| [ ] | [RA-22](tasks/release-0.4.2/RA-22.md) | CI_PASS_PENDING_NEGATIVE_CONTROL | T2 | Terra | RA-04, RA-06, RA-21 | All four native jobs passed on `2ef5e15`; repeat on corrected SHA, then remote corrupted-golden control/revert. |
| [ ] | [RA-40](tasks/release-0.4.2/RA-40.md) | CI_NOT_REACHED | T2 | Terra | RA-06, RA-08, RA-13 | Two isolated emsdk 3.1.74 builds match each other and committed JS/WASM. Workflow comparison was skipped because the Web job stopped at package dry-run in `36455663081`; repeat on corrected SHA. |
| [ ] | [RA-41](tasks/release-0.4.2/RA-41.md) | LOCAL_FIXES_CI_PENDING | T2 | Terra | RA-04, RA-21, RA-22, RA-40 | `.gitignore` exceptions now allow dry-run; scoped suppression makes `flutter analyze integration_test` pass. In run `36455663081` the Web rebuild/browser/reference steps and example builds were skipped. Rerun on corrected SHA, then remote corrupted-WASM negative control. |
| [ ] | [RA-21](tasks/release-0.4.2/RA-21.md) | REVIEW_AT_END | T2 | — | RA-06, RA-08, RA-13 | Локальные DoD пройдены: 1188 оракулов/проб на Windows, coverage/layout/copy sync. Доказательства ждут финального независимого ревью в конце цикла по указанию Engineer; Web-проба перенесена в RA-41. |
| [ ] | [RA-60](tasks/release-0.4.2/RA-60.md) | TODO | T3 | — | M1 | Фаза 4: теги `smoke`/`contract`/`probe`/`reference`/`release` в `dart_test.yaml` и в каждом файле; `flutter test` по умолчанию — только smoke + contract. |
| [ ] | [RA-61](tasks/release-0.4.2/RA-61.md) | TODO | T2 | — | RA-60 | Фаза 4: фильтр проб `PROBE_OPS`/`PROBE_FORMATS` с явной строкой среза в отчёте; эталон не меняется. |
| [ ] | [RA-62](tasks/release-0.4.2/RA-62.md) | TODO | T3 | — | RA-60, RA-61 | Фаза 4: карта «изменённые пути → команды» в AGENTS.md; те же пути — фильтры workflow. |
| [ ] | [RA-70](tasks/release-0.4.2/RA-70.md) | TODO | T2 | — | M1 | Фаза 5: соглашения разделённого CI и общие скрипты `tool/ci/`; workflow = вызов одного скрипта, который запускается и локально. |
| [ ] | [RA-71](tasks/release-0.4.2/RA-71.md) | TODO | T3 | — | RA-70 | Фаза 5: `ci-vm.yml` — analyze и VM-тесты на двух версиях Flutter. Одна джоба, вызов `tool/ci/vm`; джоба удаляется из `ci.yml`. |
| [ ] | [RA-72](tasks/release-0.4.2/RA-72.md) | TODO | T2 | — | RA-70, RA-80 | Фаза 5: `ci-windows.yml` — native build, пробы и эталон, Windows app smoke (бывшая RA-23). Одна джоба, вызов `tool/ci/windows`; джоба удаляется из `ci.yml`. |
| [ ] | [RA-73](tasks/release-0.4.2/RA-73.md) | TODO | T3 | — | RA-70 | Фаза 5: `ci-macos.yml` — native build и app smoke на macOS. Одна джоба, вызов `tool/ci/macos`; джоба удаляется из `ci.yml`. |
| [ ] | [RA-74](tasks/release-0.4.2/RA-74.md) | TODO | T3 | — | RA-70 | Фаза 5: `ci-ios.yml` — Pods, smoke и пробы на iOS Simulator, сборка без подписи. Одна джоба, вызов `tool/ci/ios`; джоба удаляется из `ci.yml`. |
| [ ] | [RA-75](tasks/release-0.4.2/RA-75.md) | TODO | T2 | — | RA-70, RA-80 | Фаза 5: `ci-android.yml` — APK трёх ABI, smoke и пробы на эмуляторе (метка `android-emulator`). Одна джоба, вызов `tool/ci/android`; джоба удаляется из `ci.yml`. |
| [ ] | [RA-76](tasks/release-0.4.2/RA-76.md) | TODO | T3 | — | RA-70 | Фаза 5: `ci-linux.yml` — единственная GitHub-hosted джоба: native, sanitizer, Linux app smoke. Одна джоба, вызов `tool/ci/linux`; джоба удаляется из `ci.yml`. |
| [ ] | [RA-77](tasks/release-0.4.2/RA-77.md) | TODO | T2 | — | RA-70, RA-80 | Фаза 5: `ci-web.yml` — dry-run, сравнение пересборки WASM, web-цели и матрица 119 (метка `web`). Одна джоба, вызов `tool/ci/web`; джоба удаляется из `ci.yml`. |
| [ ] | [RA-78](tasks/release-0.4.2/RA-78.md) | TODO | T3 | — | RA-70 | Фаза 5: `ci-example.yml` — analyze и `build web` example на 3.41.0 / 3.44.9. Одна джоба, вызов `tool/ci/example`; джоба удаляется из `ci.yml`. |
| [ ] | [RA-80](tasks/release-0.4.2/RA-80.md) | TODO | T2 | — | M1 | Фаза 5: ещё 2 Windows-раннера и при наличии ресурсов второй Mac; метки для эмулятора, Web и Pixel 3. |
| [ ] | [RA-25](tasks/release-0.4.2/RA-25.md) | REWORK | T2 | RA-41 agent | RA-13, RA-21, RA-26 | Local runner fixes bind to clean actual HEAD and strictly reject malformed/duplicate markers; focused executable tests pass 4/4. T1 re-review pending. Existing device evidence remains rejected; rerun both ABIs on accepted committed SHA and archive complete host/device evidence. |
| [ ] | [RA-26](tasks/release-0.4.2/RA-26.md) | REWORK | T2 | Terra | RA-21 | Balanced/AC is the correct contour. Diagnostics are not comparisons because `sourceVerified=false`, not because of power mode. Provenance/cleanup corrections and executable controls are local; focused copy-sync currently fails because the new root-only RA-25 test is not excluded. Clean-worktree controls and T1 re-review pending. |
| [ ] | [RA-27](tasks/release-0.4.2/RA-27.md) | TODO | T3 | — | RA-26 | Записать в AGENTS.md правило проб для задач разработки (Windows у исполнителя, Pixel 3 на ревью) и поле `Probe` в шаблон карточки. |
| [ ] | [RA-19](tasks/release-0.4.2/RA-19.md) | TODO | T3 | — | RA-71…78 | Вычистить служебные README (`tool/wasm`, `assets/wasm`, `test_native`) и комментарии CI от номеров задач после закрытия зависимостей. |
| [ ] | [RA-18](tasks/release-0.4.2/RA-18.md) | TODO | T2 | — | все RA кроме RA-50 | Финальный CHANGELOG 0.4.2 вместо черновика: фактические изменения, новый API, известные ограничения. |
| [ ] | [RA-50](tasks/release-0.4.2/RA-50.md) | TODO | T2 | — | все RA | Не начат: ждёт закрытия предыдущих RA и финального CI на одном SHA. Тег и публикация — Engineer; pub.dev publish не входит в эту работу. |

Ревью: T3 → T2; T2 → T1 (предпочтительно другой провайдер, чем исполнитель); RA-50 — T1 + Engineer; пакетное ревью — по правилу 5. Общие правила чистки документации — [DOC-RULES](tasks/release-0.4.2/DOC-RULES.md).
