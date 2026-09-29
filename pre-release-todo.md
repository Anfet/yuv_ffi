# yuv_ffi 0.4.2 — предрелизный цикл RA

Источник: предрелизный аудит 27.09.2026 (HEAD `9b41cb5`), повторная сверка 28.09.2026 на `db42681`. Карточки RA заменяют PRE-00…07 из `doc/archive/perf/prerelease-todo.md`. Архитектор — Claude Opus (T1). Engineer разрешил довести весь цикл до RA-50 по зависимостям; отдельный pub.dev publish не входит в задачу.

**Объём релиза заморожен.** VIEW-00…03 и PACK-00…01D приняты. С начала цикла RA в `lib/`, `src/`, `example/lib/` не добавляется новая функциональность; любое новое требование — отдельной карточкой после решения Engineer.

## CI и раннеры

- Правило Engineer: на GitHub-hosted — только одна Linux-джоба (`linux-native-smoke` + sanitizer). Остальное — self-hosted: `dev.working` (Windows x64: VM-матрица, Windows native, Android-эмулятор, Web/WASM, example) и `yuv-self-hosted` (macOS x64: macOS, iOS Simulator, bindings). WSL/Hyper-V не включать.
- На Windows-раннере: Android SDK `D:\.important\android-sdk`, AVD `Tablet` (API 35 x86_64), Chrome 154.0.8037.58 + ChromeDriver `D:\.projects\.tools\chromedriver-win64\chromedriver.exe`, Git Bash `D:\.important\Git\bin\bash.exe`, emsdk 3.1.74 в `D:\.projects\.tools\emsdk-3.1.74` (глобальный 5.0.1 не использовать).
- `tool/bench/` в рабочей копии принадлежит Engineer: не трогать и не коммитить.

## Состояние

В `origin/release/0.4.2` интегрированы RA-51, RA-22, RA-40, RA-21, RA-41, RA-52 и RA-53 merge commit `147f0bc064a6cce406a56561aa354aeafff183ba`; RA-53 получила T1 ACCEPT после REWORK 1. Карточный CI [36557958255](https://github.com/Anfet/yuv_ffi/actions/runs/36557958255) success 11/11 на implementation SHA `fa002379d9253f1d7777f5edc4897c83298fb9d6`. Полный release CI [36561975316](https://github.com/Anfet/yuv_ffi/actions/runs/36561975316) на merge SHA `147f0bc064a6cce406a56561aa354aeafff183ba` in progress: bindings/Linux/iOS success; Web gate и macOS packaging выполняются; Windows/Android/VM/Example jobs ждут runner slots; после его success — post-merge route/scope controls. Если release CI красный, откатить merge. RA-80 BLOCKED: `dev.working-2` offline, установка runner-службы требует Windows admin. M1 ждёт RA-53 post-merge gates и RA-80.

## Решения Engineer

| ID | Status | Вопрос | Рекомендация Architect |
| --- | --- | --- | --- |
| D-1 | DECIDED 28.09.2026 | Версия релиза при смене умолчания layout (PACK-01B). | **0.4.2.** Последняя опубликованная неотозванная версия — 0.2.4, 0.4.0 отозвана, поэтому 0.5.0 ничего не даёт. Смена умолчания описывается как **Behavior change** в CHANGELOG и отдельной строкой в таблице миграции с 0.2.4 в README: фабрики с `planes:` теперь упаковывают плоскости, для старого поведения — `layout: YuvPlaneLayout.preserve`. |
| D-2 | DECIDED 28.09.2026 | Раннеры | GitHub-hosted — только одна Linux-джоба (правило Engineer). Число self-hosted раннеров увеличивается: RA-80. |
| D-3 | DECIDED 28.09.2026 | Очерёдность RA-25/26 | После слияния RA-51 перенести готовые локальные изменения в отдельные карточные ветки и заморозить RA-25/26 до фазы 6. До этого не запускать новые Pixel- или benchmark-прогоны. |
| D-4 | DECIDED 29.09.2026 | Очерёдность CI split, запуск карточных веток и масштабирование runners | Начать RA-52 и RA-80 сейчас, до M1. RA-52 меняет только `.github/workflows/ci.yml`, не меняя job steps: pushes в `ra/**` не запускают CI; карточные ветки вручную запускают только выбранные job keys `vm`, `bindings`, `linux`, `macos`, `ios`, `android`, `windows`, `example`, `web`. Negative-control commits помечаются `[skip ci]` и проверяются одной нужной job. Полный CI запускается только на `release/**` после merge; прогоны не отменяются. Если полный прогон красный, merge откатывается. После M1 выполняются RA-70…78 — отдельный workflow на платформу; RA-60…62 переносятся после split, RA-62 строит карту путей по готовым workflow path filters. Это решение разрешает RA-52 и RA-80 до M1. |
| D-5 | DECIDED 29.09.2026 | Как карточная ветка выбирает CI | Префиксом имени ветки: `<ключи>/RA-xx` (`web/RA-41`, `windows+android/RA-90`, `all/RA-95`); push запускает только джобы этих ключей. Карта «путь → ключи» в `tool/ci/scope_guard.sh` — единственный источник: джоба на ветке падает за секунды, если префикс не покрывает изменённые пути. Общий `ci.yml` и общая инфраструктура требуют `all`; точные платформенные workflow и скрипты получают свои ключи. Поэтому RA-71…78 временно используют `all`, пока меняют общий `ci.yml`. Ручной dispatch RA-52 остаётся запасным путём. Реализация — RA-53. |

Отчёты исполнителей и ревью по карточкам цикла — в [архиве](doc/archive/release-0.4.2/ra-reports.md).

## Статусы

Базовые статусы протокола: `TODO`, `IN_PROGRESS`, `BLOCKED`, `ARCHITECT_REQUIRED`, `REVIEW`, `DONE`. По просьбе Engineer оркестратор уточняет их подстатусами, чтобы было видно, где задача сейчас. Каждый подстатус однозначно сводится к базовому и называет, кто делает следующий шаг:

| Подстатус | Базовый | Следующий шаг |
| --- | --- | --- |
| `REWORK`, `REWORK_VALIDATION_PENDING` | TODO | исполнитель: исправление и проверки |
| `REWORK_T1_REVIEW_PENDING`, `REVIEW_AT_END` | REVIEW | ревьюер (T1) |
| `REVIEW_T1_PENDING` | REVIEW | оркестратор: назначить независимого ревьюера T1 |
| `REVIEW_T1_IN_PROGRESS` | REVIEW | независимый ревьюер T1: завершить проверку |
| `LOCAL_FIXES_CI_PENDING` | IN_PROGRESS | исполнитель: коммит и CI-прогон |
| `CI_FAILED`, `CI_NOT_REACHED` | BLOCKED | исполнитель CI-карточки или владелец блокера |
| `CI_PASS_PENDING_NEGATIVE_CONTROL` | IN_PROGRESS | исполнитель: негативный контроль |

Новый подстатус добавляется в эту таблицу одновременно с первым использованием. Принятая карточка (`DONE`) сразу уходит из дашборда: краткая запись — в `COMPLETION.md`, файл карточки — `git mv` в `doc/archive/release-0.4.2/cards/` (карточки, принятые до 28.09.2026, — в `doc/archive/release-0.4.2/ra-accepted-cards.md`).

## Порядок цикла (Engineer, 28.09.2026)

| Фаза | Содержание | Карточки | Состояние |
| --- | --- | --- | --- |
| 1 | Чистка лишнего и документация | RA-01…06, RA-08, RA-10…17 | **завершена** |
| 2 | Тесты на Mac (параллельно с фазой 3): macOS native, iOS Simulator | RA-22 | **завершена**; probe negative control и восстановление приняты на `e4376ab` |
| 3 | Web | RA-40, RA-41 | **завершена**; обе карточки приняты |
| 4 | CI routing и runners | RA-52, RA-53, RA-80 до M1; RA-70…78 сразу после M1 | RA-52 DONE; **RA-53 T1 ACCEPT, MERGED** на `147f0bc`. Release CI [36561975316](https://github.com/Anfet/yuv_ffi/actions/runs/36561975316) in progress: bindings/Linux/iOS/macOS success; Web gate running на Windows; ещё 6 jobs queued. Ждём полный результат; при success — post-merge route/scope controls, при failure — откат merge. RA-80 BLOCKED на Windows admin |
| **M1** | **Стабильный предрелиз:** фазы 1–3 закрыты, полный CI зелёный на одном SHA `release/0.4.2` | — | после RA-52, RA-53 и RA-80 |
| 5 | Декомпозиция тест-сьюта: запускать только нужное | RA-60…RA-62 | после RA-70…78 |
| 6 | Устройство и скорость | RA-25, RA-26, RA-27 | после фазы 5 |
| 7 | Релиз | RA-19, RA-18, RA-50 | последней |

Решение Engineer D-4 разрешает RA-52 и RA-80 до M1. Остальные карточки запускаются по зависимостям после M1. RA-25/RA-26 продолжаются только в той части, которая уже в работе; новые прогоны на устройстве — после platform split.

## Правила работы (Engineer, 28.09.2026)

1. **Одна карточка — одна ветка.** Исполнитель работает в ветке `<ключи>/RA-xx` от `release/0.4.2` (D-5): ключи CI по карте `tool/ci/scope_guard.sh` — `all`, `vm`, `bindings`, `linux`, `macos`, `ios`, `android`, `windows`, `web`, `example`, несколько через `+`. Префикс выбирает исполнитель, оркестратор сверяет его с Scope карточки при запуске. До слияния RA-53 — `ra/RA-xx`; при параллельной работе — в отдельном worktree `D:\.projects\yuv_ffi-wt\RA-xx`. В коммит попадают только файлы своей карточки. CI и ревью проверяют SHA ветки карточки. После приёмки оркестратор вливает ветку в `release/0.4.2`; M1 и RA-50 фиксируются только на SHA `release/0.4.2`. Общая рабочая копия `D:\.projects\yuv_ffi` — не место для незакоммиченной работы карточек.
2. **Локальная проверка, выбор CI и лимит итераций.** Перед push исполнитель выполняет Validation карточки. После RA-53 push в карточную ветку сам запускает джобы её префикса; если префикс не покрывает изменённые пути, джоба падает за секунды с сообщением `scope: …` — ветку переименовать, а не обходить проверку. До RA-53 (ветки `ra/**`) — ручной запуск RA-52: `gh workflow run ci.yml --ref ra/RA-xx -f jobs=web`, коммиты негативного контроля с `[skip ci]`. Откат негативного контроля пушится только после завершения контрольного прогона, иначе concurrency его отменит. Полный CI — только на `release/**` после merge; такие прогоны не отменяются; красный полный прогон — откат merge, карточка в `REWORK`. После RA-70 локально запускаются `tool/ci/<name>`. Два красных прогона по одной причине, которую не удалось воспроизвести локально, — карточка переходит в `ARCHITECT_REQUIRED`, третьей попытки нет.
3. **Карточка — отдельный файл** `tasks/release-0.4.2/RA-xx.md`. Этот файл содержит только правила, порядок и дашборд. Дашборд и статусы правит только оркестратор; при расхождении статус дашборда главнее. Карточку правят архитектор (решение, DoD) и исполнитель (раздел `#### Executor Report` в конце). Исполнитель читает свою карточку и этот файл, остальные — по ссылке из Depends On.
4. **Решение `ARCHITECT_REQUIRED`.** Оркестратор вызывает Sol с reasoning medium для решения; карточка не останавливает фазу: остальные карточки продолжаются, вопросы собираются в общий список. Разбор с архитектором и Engineer — одной сессией на границе фазы или раз в день.
5. **Строгость ревью по риску.** Независимое ревью каждой карточки — для контракта API, native, проб и golden, CI-логики и релизных скриптов. Документация, чистка, перенос в архив и правки только комментариев принимаются одним пакетным ревью на фазу.
6. **Одна фаза за раз.** До M1 новые карточки создаются только для того, что блокирует M1; решение Engineer D-4 разрешает начать RA-52 и RA-80. После M1 выполняются RA-70…78, затем RA-60…62. Фазы 2 (Mac) и 3 (Web) можно вести параллельно — разные раннеры и разный код.

## Дашборд

Порядок — по фазам цикла; ID ведёт к файлу карточки; Summary — текущее состояние и следующий шаг.

| Done | ID | Status | Tier | Owner | Depends On | Summary |
| --- | --- | --- | --- | --- | --- | --- |
| [x] | [RA-41](doc/archive/release-0.4.2/cards/RA-41.md) | DONE | T2 | Terra | RA-04, RA-21, RA-22, RA-40 | T1 ACCEPT на `8d96b84`; CI `36534765261` success 11/11, Web gate и matrix PASS. |
| [ ] | [RA-53](tasks/release-0.4.2/RA-53.md) | IN_PROGRESS | T2 | Orchestrator: full release CI, затем post-merge checks | RA-52 | T1 ACCEPT, merge SHA `147f0bc064a6cce406a56561aa354aeafff183ba`. Release CI [36561975316](https://github.com/Anfet/yuv_ffi/actions/runs/36561975316) in progress: bindings/Linux/iOS/macOS success; Web gate running на Windows, остальные 6 jobs queued. После полного success выполнить post-merge route/scope controls. |
| [ ] | [RA-80](tasks/release-0.4.2/RA-80.md) | BLOCKED | T2 | Terra | D-4 | `dev.working-2` зарегистрирован, но offline: установка службы требует Windows admin. Labels добавлены на текущий runner; параллельность ждёт elevated-сеанс. |
| [ ] | [RA-70](tasks/release-0.4.2/RA-70.md) | TODO | T2 | — | M1, RA-52, RA-80 | После M1: соглашения split CI и общие локально запускаемые `tool/ci/` scripts. |
| [ ] | [RA-71](tasks/release-0.4.2/RA-71.md) | TODO | T3 | — | RA-70 | После M1: `ci-vm.yml` на двух версиях Flutter. |
| [ ] | [RA-72](tasks/release-0.4.2/RA-72.md) | TODO | T2 | — | RA-70, RA-80 | После M1: `ci-windows.yml` — native build, probes и Windows app smoke. |
| [ ] | [RA-73](tasks/release-0.4.2/RA-73.md) | TODO | T3 | — | RA-70 | После M1: `ci-macos.yml` — native build и macOS app smoke. |
| [ ] | [RA-74](tasks/release-0.4.2/RA-74.md) | TODO | T3 | — | RA-70 | После M1: `ci-ios.yml` — Pods, smoke и Simulator probes. |
| [ ] | [RA-75](tasks/release-0.4.2/RA-75.md) | TODO | T2 | — | RA-70, RA-80 | После M1: `ci-android.yml` — APK ABI, smoke и emulator probes. |
| [ ] | [RA-76](tasks/release-0.4.2/RA-76.md) | TODO | T3 | — | RA-70 | После M1: `ci-linux.yml` — единственный GitHub-hosted Linux workflow. |
| [ ] | [RA-77](tasks/release-0.4.2/RA-77.md) | TODO | T2 | — | RA-70, RA-80 | После M1: `ci-web.yml` — WASM rebuild, Web targets и matrix 119. |
| [ ] | [RA-78](tasks/release-0.4.2/RA-78.md) | TODO | T3 | — | RA-70 | После M1: `ci-example.yml` — analyze/build на 3.41.0 и 3.44.9. |
| [ ] | [RA-60](tasks/release-0.4.2/RA-60.md) | TODO | T3 | — | RA-70…78 | После split: теги smoke/contract/probe/reference/release; default `flutter test` — smoke + contract. |
| [ ] | [RA-61](tasks/release-0.4.2/RA-61.md) | TODO | T2 | — | RA-60 | После RA-60: фильтры `PROBE_OPS`/`PROBE_FORMATS` без изменения golden. |
| [ ] | [RA-62](tasks/release-0.4.2/RA-62.md) | TODO | T3 | — | RA-60, RA-61, RA-71…78 | После split: карта путей→команды по готовым path filters. |
| [ ] | [RA-25](tasks/release-0.4.2/RA-25.md) | REWORK | T2 | RA-41 agent | RA-13, RA-21, RA-26 | Local runner fixes bind to clean actual HEAD and strictly reject malformed/duplicate markers; focused executable tests pass 4/4. T1 re-review pending. Existing device evidence remains rejected; rerun both ABIs on accepted committed SHA and archive complete host/device evidence. |
| [ ] | [RA-26](tasks/release-0.4.2/RA-26.md) | REWORK | T2 | Terra | RA-21 | Balanced/AC is the correct contour. Diagnostics are not comparisons because `sourceVerified=false`, not because of power mode. Provenance/cleanup corrections and executable controls are local; focused copy-sync currently fails because the new root-only RA-25 test is not excluded. Clean-worktree controls and T1 re-review pending. |
| [ ] | [RA-27](tasks/release-0.4.2/RA-27.md) | TODO | T3 | — | RA-26 | Записать в AGENTS.md правило проб для задач разработки (Windows у исполнителя, Pixel 3 на ревью) и поле `Probe` в шаблон карточки. |
| [ ] | [RA-19](tasks/release-0.4.2/RA-19.md) | TODO | T3 | — | RA-71…78 | Вычистить служебные README (`tool/wasm`, `assets/wasm`, `test_native`) и комментарии CI от номеров задач после закрытия зависимостей. |
| [ ] | [RA-18](tasks/release-0.4.2/RA-18.md) | TODO | T2 | — | все RA кроме RA-50 | Финальный CHANGELOG 0.4.2 вместо черновика: фактические изменения, новый API, известные ограничения. |
| [ ] | [RA-50](tasks/release-0.4.2/RA-50.md) | TODO | T2 | — | все RA | Не начат: ждёт закрытия предыдущих RA и финального CI на одном SHA. Тег и публикация — Engineer; pub.dev publish не входит в эту работу. |

Ревью: T3 → T2; T2 → T1 (предпочтительно другой провайдер, чем исполнитель); RA-50 — T1 + Engineer; пакетное ревью — по правилу 5. Общие правила чистки документации — [DOC-RULES](tasks/release-0.4.2/DOC-RULES.md).
