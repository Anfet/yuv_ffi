# yuv_ffi 0.4.2 — план выпуска

**Цель:** выпустить yuv_ffi 0.4.2. Порядок (решение Engineer D-6): **сначала финальный код, потом CI и проверки, потом выпуск.** Этапы идут строго по очереди.

| Этап | Что | Итог этапа |
| --- | --- | --- |
| **1. Финальный код** | Уборка, служебные README, CHANGELOG, README. CI не запускается — меняются только `.md`, проверки локальные | SHA релиз-кандидата (РК); код пакета заморожен |
| **2. CI и проверки** | Доделать маршрутизацию CI, ускорить Web, разделить CI по платформам, разметить тесты; прогнать всё на РК и Pixel 3 | Все платформы зелёные на одном SHA, код не отличается от РК |
| **3. Выпуск** | Финальный гейт и отчёт Engineer | Тег и публикация — Engineer |

Объём релиза заморожен: новая функциональность в `lib/`, `src/`, `example/lib/` не добавляется.

## Где мы сейчас

- **Сделано:** чистка репозитория и документации, пробы корректности (1188 случаев) на Windows, Linux, macOS, iOS, Android и Web, пересобранный WASM, запуск CI по префиксу ветки. Последний полный CI: run [36630795431](https://github.com/Anfet/yuv_ffi/actions/runs/36630795431), 11/11 PASS на `e6a1eab`. Ускорение native-ядер (C-01…C-11) принято раньше.
- **Сейчас:** RA-25 и RA-79 завершены и архивированы после Engineer ACCEPT и полного release CI [36630795431](https://github.com/Anfet/yuv_ffi/actions/runs/36630795431): 11/11 jobs PASS на `e6a1eabb0fbe36750853caad98c059ea838447d2`. RA-56 (`b5de994`, Web CI [36638775604](https://github.com/Anfet/yuv_ffi/actions/runs/36638775604) PASS за 5:10) и RA-70 (`f1557b6`, smoke [36619948343](https://github.com/Anfet/yuv_ffi/actions/runs/36619948343) PASS) приняты ревью 30.09 и ждут слияния и полного release CI. RA-71…78 остаются BLOCKED до интеграции RA-70; RA-77 также зависит от RA-56. Pub.dev публикации не будет.
- **SHA РК:** `a4f17c1efa2d0098e39deb59361cea5597eb06cb` (29.09.2026), принят T1; замороженные пути не менялись.

## Дашборд

ID ведёт к файлу карточки; Summary начинается с понятного названия.

### Этап 1 — финальный код

| Done | ID | Status | Tier | Owner | Depends On | Summary |
| --- | --- | --- | --- | --- | --- | --- |
| [x] | [RA-54](doc/archive/release-0.4.2/cards/RA-54.md) | DONE | T3 | Terra (T2 takeover) | — | **Прибрана рабочая копия и ветки.** T1 ACCEPT на `f4b100d`; rejection count 2. Проверка состояния репозитория подтверждена на `c039d8c`; runner 24 и лишние worktree/refs удалены, `tool/bench/` сохранён. |
| [x] | [RA-19](doc/archive/release-0.4.2/cards/RA-19.md) | DONE | T3 | Terra (T2 takeover) | — | **Служебные README очищены от номеров задач.** T1 ACCEPT на `4d1bbdd`; rejection count 2. DOC-RULES: 0 совпадений, ссылки проверены. |

RA-19 и RA-18 — одно пакетное ревью (документы).

### Этап 2 — CI и проверки

| Done | ID | Status | Tier | Owner | Depends On | Summary |
| --- | --- | --- | --- | --- | --- | --- |
| [ ] | [RA-56](tasks/release-0.4.2/RA-56.md) | MERGE_CI_PENDING | T2 | GPT-5.6 Terra (`all/RA-56-rework`) | RA-55, RA-79 | **Web-ускорение принято ревью 30.09.** Код `b5de994`, report `c8bf3c0`; Web CI [36638775604](https://github.com/Anfet/yuv_ffi/actions/runs/36638775604) PASS за 5:10; негативные контроли приняты. Следующий шаг: слияние и полный release CI. Rejection count: 2. |
| [ ] | [RA-70](tasks/release-0.4.2/RA-70.md) | MERGE_CI_PENDING | T2 | GPT-5.6 Terra (`all/RA-70`, `f1557b6`) | RA-53, RA-55 | **Общие правила CI приняты ревью 30.09.** Временный tag trigger и исключение scope guard удалены, remote tag отсутствует; smoke [36619948343](https://github.com/Anfet/yuv_ffi/actions/runs/36619948343) PASS. Следующий шаг: слияние и полный release CI. Rejection count: 1. |
| [ ] | [RA-71](tasks/release-0.4.2/RA-71.md) | BLOCKED | T3 | RA-70 merge/CI | RA-70 | **Ждёт интеграции RA-70 и полного release CI:** затем отдельный workflow VM-тестов на двух версиях Flutter. |
| [ ] | [RA-72](tasks/release-0.4.2/RA-72.md) | BLOCKED | T2 | RA-70 merge/CI | RA-70 | **Ждёт интеграции RA-70 и полного release CI:** затем отдельный Windows workflow для native build, проб и app smoke. |
| [ ] | [RA-73](tasks/release-0.4.2/RA-73.md) | BLOCKED | T3 | RA-70 merge/CI | RA-70 | **Ждёт интеграции RA-70 и полного release CI:** затем отдельный macOS workflow для native build и app smoke. |
| [ ] | [RA-74](tasks/release-0.4.2/RA-74.md) | BLOCKED | T3 | RA-70 merge/CI | RA-70 | **Ждёт интеграции RA-70 и полного release CI:** затем отдельный iOS workflow для Pods, симулятора и проб. |
| [ ] | [RA-75](tasks/release-0.4.2/RA-75.md) | BLOCKED | T2 | RA-70 merge/CI | RA-70 | **Ждёт интеграции RA-70 и полного release CI:** затем отдельный Android workflow для трёх ABI, эмулятора и проб. |
| [ ] | [RA-76](tasks/release-0.4.2/RA-76.md) | BLOCKED | T3 | RA-70 merge/CI | RA-70 | **Ждёт интеграции RA-70 и полного release CI:** затем отдельный Linux workflow; это единственная GitHub-hosted job. |
| [ ] | [RA-77](tasks/release-0.4.2/RA-77.md) | BLOCKED | T2 | RA-70/56 merge/CI | RA-70, RA-56 | **Ждёт интеграции RA-70 и RA-56 и полного release CI:** затем отдельный Web workflow для WASM, browser tests и эталонной матрицы. |
| [ ] | [RA-78](tasks/release-0.4.2/RA-78.md) | BLOCKED | T3 | RA-70 merge/CI | RA-70 | **Ждёт интеграции RA-70 и полного release CI:** затем отдельный example workflow с analyze и сборкой на Flutter 3.41.0 и 3.44.9. |
| [ ] | [RA-60](tasks/release-0.4.2/RA-60.md) | BLOCKED | T3 | Предыдущие карточки | RA-70…78 | **Ждёт завершения платформенных workflow RA-71…78:** затем разметить тесты тегами, оставив по умолчанию smoke + contract. |
| [ ] | [RA-61](tasks/release-0.4.2/RA-61.md) | BLOCKED | T2 | RA-60 | RA-60 | **Ждёт RA-60:** затем добавить выбор операции/формата и явный отчёт о выполненном срезе проб. |
| [ ] | [RA-62](tasks/release-0.4.2/RA-62.md) | BLOCKED | T3 | RA-60/61 | RA-60, RA-61 | **Ждёт RA-60 и RA-61:** затем описать карту «что изменил → что запускать» по `tool/ci/scope_guard.sh`. |
| [ ] | [RA-57](tasks/release-0.4.2/RA-57.md) | BLOCKED | T2 | Предыдущие карточки | RA-53, RA-56, RA-70…78, RA-60…62 | **Ждёт завершения всех платформенных workflow и RA-60…62:** после этого проверить все платформы на одном SHA и равенство кода РК. |

Порядок внутри этапа: RA-53 и RA-56 → RA-70 → RA-71…78 (параллельно, по одной платформе) → RA-60…62 → RA-57. RA-25 идёт параллельно с самого начала этапа. Если проверка нашла дефект в коде: карточка «Исправление: …» → повтор RA-55 (новый SHA РК) → повтор упавших проверок.

### Этап 3 — выпуск

| Done | ID | Status | Tier | Owner | Depends On | Summary |
| --- | --- | --- | --- | --- | --- | --- |
| [ ] | [RA-50](tasks/release-0.4.2/RA-50.md) | BLOCKED | T2 | RA-57/RA-25 | RA-57, RA-25 | **Ждёт RA-57 и интеграционного release CI для принятой RA-25:** затем финальный гейт на одном SHA, равенство кода РК, dry-run и отчёт Engineer. Pub.dev publish не входит в релиз. |

### После релиза 0.4.2

| ID | Что |
| --- | --- |
| [RA-26](tasks/release-0.4.2/RA-26.md) | Замеры скорости HEAD против 0.4.0 на Windows и Pixel 3 (незакоммиченная работа — в ветке `all/RA-26`). |
| [RA-27](tasks/release-0.4.2/RA-27.md) | Правило проб для задач разработки в `AGENTS.md`. |
| [RA-80](tasks/release-0.4.2/RA-80.md) | Дополнительные раннеры — для 0.4.2 не нужны (D-6). |

Общие правила чистки документации — [DOC-RULES](tasks/release-0.4.2/DOC-RULES.md). Отчёты и ревью принятых карточек — в [архиве](doc/archive/release-0.4.2/ra-reports.md) и `doc/archive/release-0.4.2/cards/`.

## Правила работы

1. **Этапы по очереди.** Карточки этапа 2 не начинаются до заморозки РК (RA-55). После заморозки замороженные пути (список в RA-55) меняются только карточкой «Исправление: …»; после неё RA-55 повторяется.
2. **Одна карточка — одна ветка** `<ключи>/RA-xx` от `release/0.4.2`, при параллельной работе — свой worktree `D:\.projects\yuv_ffi-wt\RA-xx`. Ключи CI: `all`, `vm`, `bindings`, `linux`, `macos`, `ios`, `android`, `windows`, `web`, `example`, несколько через `+`; префикс выбирается по карте `tool/ci/scope_guard.sh` и сверяется оркестратором со Scope карточки. Карточка, меняющая только `.md`, — ветка `docs/RA-xx`, CI не запускается. В коммит — только файлы своей карточки. Основная рабочая копия `D:\.projects\yuv_ffi` — не место для незакоммиченной работы.
3. **Сначала локально, потом CI.** Перед push исполнитель выполняет Validation карточки локально. Push в ветку запускает только джобы её префикса; если префикс уже изменённых путей — джоба падает за секунды с `scope: …`, ветку переименовать. Откат негативного контроля пушится только после завершения контрольного прогона. Два красных прогона по одной причине, не воспроизведённой локально, — `ARCHITECT_REQUIRED`, третьей попытки нет.
4. **Полный CI — только на `release/**`** после слияния; такие прогоны не отменяются; красный — откат слияния, карточка в `REWORK`.
5. **Карточка — отдельный файл** `tasks/release-0.4.2/RA-xx.md`. Дашборд и статусы правит только оркестратор; при расхождении главнее дашборд. Summary в дашборде начинается с понятного названия задачи. Карточку правят архитектор (решение, DoD) и исполнитель (раздел `#### Executor Report`). Принятая карточка уходит из дашборда: краткая запись — в `COMPLETION.md`, файл — `git mv` в `doc/archive/release-0.4.2/cards/`.
6. **Коммиты статуса — только при смене статуса карточки.** Прогресс отдельных джоб CI не коммитить: он виден в GitHub.
7. **`ARCHITECT_REQUIRED` не останавливает этап:** остальные карточки идут дальше, вопросы копятся и разбираются одной сессией.
8. **Пакетное ревью.** Когда готовы 2–4 карточки, оркестратор назначает один пакетный вызов подходящего ревьюера; в пакете каждая карточка проверяется отдельно по своему DoD, но ревьюер не берёт соседние исправления и задачи. Документация и уборка собираются к концу этапа. Отдельный вызов для одной карточки допустим только если она блокирует критический следующий шаг или Engineer явно просит срочный разбор; причину записать в дашборд.
9. **Язык (D-7).** Внешнее — на английском: `README.md`, `CHANGELOG.md`, `example/README.md`, dartdoc и комментарии в коде (Dart, native C, тесты, `tool/`), комментарии workflow, сообщения коммитов, тексты ошибок. Внутреннее — на русском: `AGENTS.md`, `todo.md`, этот файл, `COMPLETION.md`, карточки, статусы, решения, отчёты, `doc/archive/**`. Имена файлов, символов, команд, ключи CI и цитаты из логов не переводятся.
10. **Ограничения Engineer.** `tool/bench/` не трогать и не коммитить. На GitHub-hosted — только Linux-джоба, остальное на self-hosted `dev.working` (Windows) и `yuv-self-hosted` (Mac). WSL/Hyper-V не включать. Native C — только с разрешения Engineer. Тег и публикация — Engineer.

## Окружение

- Windows-раннер `dev.working`: Android SDK `D:\.important\android-sdk`, AVD `Tablet` (API 35 x86_64), Chrome 154.0.8037.58 + ChromeDriver `D:\.projects\.tools\chromedriver-win64\chromedriver.exe`, Git Bash `D:\.important\Git\bin\bash.exe`, emsdk 3.1.74 в `D:\.projects\.tools\emsdk-3.1.74` (глобальный 5.0.1 не использовать).
- Mac-раннер `yuv-self-hosted`: macOS, iOS Simulator, bindings.

## Статусы

`TODO`, `IN_PROGRESS`, `BLOCKED`, `ARCHITECT_REQUIRED`, `REVIEW`, `DONE` — по протоколу. Уточнения оркестратора:

| Подстатус | Базовый | Кто делает следующий шаг |
| --- | --- | --- |
| `REWORK`, `REWORK_VALIDATION_PENDING` | TODO | исполнитель: исправление и проверки |
| `REVIEW_T1_PENDING`, `REVIEW_T1_IN_PROGRESS`, `REWORK_T1_REVIEW_PENDING` | REVIEW | ревьюер T1; пакетный вызов при 2–4 готовых карточках |
| `LOCAL_FIXES_CI_PENDING` | IN_PROGRESS | исполнитель: коммит и CI |
| `CI_FAILED`, `CI_NOT_REACHED` | BLOCKED | владелец блокера |
| `CI_PASS_PENDING_NEGATIVE_CONTROL` | IN_PROGRESS | исполнитель: негативный контроль |
| `MERGE_CI_PENDING` | IN_PROGRESS | оркестратор: merge и полный release CI после освобождения раннера |
| `DEFERRED` | — | перенесено; причина в карточке |

Новый подстатус добавляется сюда одновременно с первым использованием.

## Решения Engineer

| ID | Дата | Решение |
| --- | --- | --- |
| D-1 | 28.09.2026 | Версия — **0.4.2** (0.4.0 отозвана, опубликована 0.2.4). Смена умолчания `YuvPlaneLayout.packed` — пункт **Behavior change** в CHANGELOG и строка в таблице миграции README. |
| D-2 | 28.09.2026 | На GitHub-hosted — только Linux-джоба; остальное — self-hosted. |
| D-5 | 29.09.2026 | CI карточной ветки выбирается префиксом имени `<ключи>/RA-xx`; карта «путь → ключи» — `tool/ci/scope_guard.sh`. Ручной `workflow_dispatch -f jobs=…` — запасной путь. |
| D-6 | 29.09.2026 | Порядок выпуска: **финальный код → CI и проверки → выпуск.** Заменяет D-3 и D-4. Второй раннер для 0.4.2 не нужен (RA-80 после релиза); замеры скорости и правило проб — после релиза; Pixel 3 — одна попытка на коде РК. |
| D-7 | 29.09.2026 | Язык документов — правило 9. |
