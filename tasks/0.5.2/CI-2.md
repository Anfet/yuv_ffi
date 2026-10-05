# CI 2 — Web CI на Mac
**Status:** DONE · **Tier:** T2, Reviewer T1 · **Owner:** — · **Depends On:** — · **Probe:** none

**Base SHA:** `aa0b0af38ee4d6a7258e63a9bfd7a19e4f387c93`

#### Goal

Web CI (`ci-web.yml`) идёт на self-hosted Mac `yuv-self-hosted`, а не на Windows-машине `dev.working`. После карточки:
`tool/ci/web.sh` выполняет те же проверки, что `tool/ci/web.ps1`; workflow `CI Web` запускает его на Mac; запуск на
принятом SHA зелёный. Windows-машина освобождается от самой долгой браузерной задачи `ci/all`.

Карточка идёт до выпуска 0.5.1 (D-31): гейт RELEASE 1 уже пройден на `61da2ee` (`ci/all/0.5.1` 9/9), а CI 2
меняет только `tool/` и `.github/`, которые в список заморозки не входят и в пакет не попадают.

#### Diagnosis

Проверено 05.10.2026 вручную на Mac (`~/projects/yuv_ffi`, ветка `release/0.5.1`, тот же код, что в `dev`). Эти факты
нужны только на старте.

- Mac arm64: Chrome 154.0.8037.95, ChromeDriver 154.0.8037.57 (`~/bin/chromedriver`), одна major-версия. Python
  системный 3.9.6; `emsdk` из `master` его отвергает («requires python 3.10»), тег `3.1.74` работает.
- emsdk 3.1.74 поставлен в `~/storage/emsdk-3.1.74` (`git checkout 3.1.74`, затем `install` / `activate`).
- **Сборка WASM воспроизводима между Windows и Mac.** `assets/wasm/yuv_ffi.js` и `.wasm` совпали побайтово с
  закоммиченными (`cmp -l` — 0 расхождений, одинаковый `shasum`). Единственное расхождение для Git — режим файла:
  `emcc` на macOS создаёт `.wasm` с `0755`, в коммите `0644`; лечится `chmod 644` после сборки.
- Черновик `tool/ci/web.sh` (коммит с этой карточкой) прогнан на Mac целиком: exit 0, `Web CI passed: Chrome
  154.0.8037.95; sources=14; integration cases=64; reference matrix=119; camera smoke=1.`, `--wasm` — 3 цели за 57 с.
  Черновик не ревьюился и не подключён к workflow.
- `probe_web_test.dart` — проверка точных значений по golden, замера скорости и baseline в нём нет, поэтому перенос
  раннера baseline не меняет.
- Раннер `yuv-self-hosted`: ОС macOS, метки `self-hosted`, `macOS`, `X64` (метки `web` нет; на Windows-раннере она
  есть). Тот же раннер обслуживает `ci-macos.yml`, `ci-ios.yml` и задание в `ci.yml`: один раннер — одно задание.
- В клоне Mac после проб остались неотслеживаемый `tool/ci/web.sh` и `M assets/wasm/yuv_ffi.wasm` (только режим файла).
  Перед работой привести клон к SHA `dev`: удалить неотслеживаемый файл, `git checkout -- assets/wasm`.

#### Architect Decision

1. **Раннер.** `ci-web.yml` переводится на Mac целиком: один workflow — одна платформа (`AGENTS.md`), второй
   Windows-workflow не заводится. `tool/ci/web.ps1` остаётся: это локальная проверка Executor на Windows (проба `web`
   в `AGENTS.md`) и запасной путь отката.
2. **Скрипт.** Основа — `tool/ci/web.sh` из черновика, шаги те же, что в `web.ps1`. Матрица источников (14 файлов, 64
   случая, 119 reference, 1 camera smoke) дублируется в двух скриптах; расхождение ловит DoD 6. Общий файл
   матрицы не выделяется (вне задачи).
3. **Метки `runs-on`.** A1 (первая попытка): `[self-hosted, macOS, X64]`, как у `ci-macos.yml`; метки раннера не
   менять. A2: если задание не берётся раннером или берётся не тем, Engineer добавляет раннеру метку `web` —
   `ENGINEER_REQUIRED` с этим вопросом и рекомендацией A2 (`[self-hosted, macOS, web]`). Не угадывать метку.
4. **Окружение Mac.** Скрипт сам берёт Chrome из `/Applications/Google Chrome.app`, драйвер из `~/bin/chromedriver`,
   emsdk из `~/storage/emsdk-3.1.74` (переопределяется `CHROME_EXECUTABLE`, `CHROMEDRIVER_EXE`, `EMSDK_ROOT`).
   Совпадение major-версий Chrome и драйвера проверяется и роняет прогон. Обновление Chrome без драйвера — отказ
   CI, а не диагноз Executor (`ci.md` §4).
5. **Режим `.wasm`.** `chmod 644 assets/wasm/yuv_ffi.wasm` до `pub publish --dry-run` и после сборки; без этого
   dry-run даёт предупреждение «checked-in file is modified», а `git diff --exit-code` — ложное расхождение.
6. **Документы.** `AGENTS.md` проекта («Локальные проверки», «CI») получает строку про `web.sh` на Mac; `MACHINES.md`
   (`D:\.projects`, вне репозитория) и `todo.md` («Окружение») — по решению Engineer, Executor предлагает текст в отчёте.
7. **Очередь.** `ci/all` теперь ставит `web` в одну очередь с `macos`, `ios` и заданием `ci.yml`. Время `ci/all`
   записывается в отчёт; если оно выросло неприемлемо — `ENGINEER_REQUIRED` с цифрами, а не откат по своему решению.

#### Scope

`tool/ci/web.sh`, `.github/workflows/ci-web.yml`, строки про Web CI в `AGENTS.md` проекта. Остальное не менять.

#### Constraints

- `tool/ci/web.ps1`, `tool/ci/drive.*`, `tool/wasm/**`, `assets/wasm/**`, `src/**`, `lib/**`, `example/**` не менять.
- Закоммиченные WASM-артефакты не пересобирать и не коммитить: расхождение `git diff --exit-code` — отказ, не повод
  обновить файлы.
- Не менять тесты, golden и baseline ради зелёного прогона.
- Не менять и не перезапускать службы раннера; метки — только Engineer (A2).
- Бит `0755` у `.wasm` не попадает в индекс.

#### Definition of Done

1. `tool/ci/web.sh` — в индексе с режимом `100755`, синтаксис верен — check: `git ls-files -s tool/ci/web.sh` → первая
   колонка `100755`; `bash -n tool/ci/web.sh` → exit 0 — by: Executor
2. В репозитории нет второго определения Web-матрицы, расходящегося с `web.ps1` — check: `rg -c "sources=14; integration
   cases=64; reference matrix=119; camera smoke=1" tool/ci/web.ps1 tool/ci/web.sh` → по `1` в каждом файле; список
   `$aggregate` / `aggregate=(` и `$separate` / `separate=(` — те же 9 и 5 имён (чтение двух файлов рядом) — by: Executor
3. Локальный прогон на Mac на SHA карточки, из чистого клона — check: на Mac `git status --short` пуст, затем
   `bash tool/ci/web.sh` → exit 0 и последняя строка `Web CI passed: Chrome <версия>; sources=14; integration
   cases=64; reference matrix=119; camera smoke=1.`; после прогона `git status --short` пуст — by: Executor
4. Негативный контроль — check: во временной копии на Mac (`/tmp`, не в репозитории) сломать один тест из
   `example/integration_test/all_web_test.dart` (например, перевернуть ожидание), `bash tool/ci/web.sh` → exit ≠ 0
   и в выводе нет `Web CI passed`; копию удалить — by: Executor
5. Скрипт роняет прогон при расхождении WASM — check: во временной копии на Mac дописать байт в
   `assets/wasm/yuv_ffi.js`, `bash tool/ci/web.sh` → exit ≠ 0 на шаге `git diff --exit-code`; копию удалить — by: Executor
6. `ci-web.yml` — `runs-on: [self-hosted, macOS, X64]` (A1) или метки по решению Engineer (A2), шаг запускает
   `bash ./tool/ci/web.sh` — check: чтение diff против этого пункта — by: Reviewer
7. Запуск workflow на SHA карточки зелёный на Mac — check: `gh workflow run ci-web.yml --ref dev`, затем
   `gh run watch <run-id> --exit-status` → exit 0; `gh run view <run-id> --json headSha,jobs --jq '.headSha, .jobs[].runnerName'`
   → SHA карточки и `yuv-self-hosted` — by: Executor
8. Время `ci/all` с Web на Mac записано — check: `ci/all/CI-2` на SHA карточки, в отчёте таблица «workflow → run →
   длительность»; сравнение с последним `ci/all` на 0.5.1 (`gh run list --workflow ci-web.yml`) — by: Executor
9. Документация — check: `rg -n "web.sh" AGENTS.md` → есть строка в «Локальных проверках» или «CI», Windows-путь
   `web.ps1` не удалён — by: Executor

#### Validation

Минимум: DoD 1–5 на Mac локально, 7 — запуск workflow. DoD 8 (`ci/all`) — один раз, после принятия остального.
Теги `ci/*` — триггеры; удаляются пачкой в конце цикла (`todo.md`, правило 4). Пробы по `AGENTS.md`: пути карточки —
`tool/` и CI — `none`; `web.ps1` как проба Executor не меняется.

#### Executor Report

Validated at: `51eb04189a084f6ada5f0cfb0e3553bf3adfeafa`
1. `tool/ci/web.sh` — `git ls-files -s tool/ci/web.sh`; `bash -n tool/ci/web.sh` — `100755`; exit 0.
2. Web matrix — `rg -c "sources=14; integration cases=64; reference matrix=119; camera smoke=1" tool/ci/web.ps1 tool/ci/web.sh`; read `$aggregate`/`aggregate` and `$separate`/`separate` arrays — one summary per script; same 9 aggregate and 5 separate sources.
3. Clean Mac clone — `bash tool/ci/web.sh` — exit 0; `Web CI passed: Chrome 154.0.8037.95; sources=14; integration cases=64; reference matrix=119; camera smoke=1.`; clone clean after run.
4. Temporary Mac clone with a committed inverted `getBytes` length expectation — `bash tool/ci/web.sh` — exit 1 in `all_web_test.dart`, expected length 5 / actual 4; no `Web CI passed`.
5. Temporary Mac clone with a committed extra byte in `assets/wasm/yuv_ffi.js` — `bash tool/ci/web.sh` — exit 1 at `git diff --exit-code`; no `Web CI passed`.
6. Workflow and runner — read `.github/workflows/ci-web.yml` diff — `runs-on: [self-hosted, macOS, X64]`; invokes `bash ./tool/ci/web.sh`.
7. GitHub workflow — run 37301435314, `gh run watch 37301435314 --exit-status` — exit 1 on SHA `51eb04189a084f6ada5f0cfb0e3553bf3adfeafa`, runner `yuv-self-hosted`; browser matrix and reference test passed, then camera smoke failed with `A CameraController was used after being disposed.`
8. `ci/all` — not run; waiting for DoD 7 to pass.
9. Documentation — `rg -n "web.sh" AGENTS.md` — Mac `web.sh` and local Windows `web.ps1` documented.
Deviations: First workflow attempt exposed that Flutter was absent from the runner's non-login `PATH`; `web.sh` now resolves `FLUTTER_ROOT` from PATH or `~/storage/flutter_3.44/flutter`. The next run reached the camera smoke test and failed as recorded in item 7.
Engineer attention: CI 2 is blocked by the failed camera smoke test outside Scope. Per `D:\.projects\.protocol\ci.md` §4, Engineer to decide whether to retry CI or authorize work outside this card's Scope. DoD 7 green and DoD 8 remain outstanding.

#### Review

Ревью диапазона `aa0b0af..754bbdd` и отчёта против карточки с учётом D-32, 05.10.2026.

**Вердикт:** принято, SHA `754bbdd` (код — `51eb041`, `Validated at`). `DONE`.

- DoD 1, 2, 3, 4, 5, 9 — по отчёту; режим `100755` у `tool/ci/web.sh` в индексе виден в `git ls-files -s`.
- DoD 6 (Reviewer) — `ci-web.yml`: `runs-on: [self-hosted, macOS, X64]` (A1), шаг `bash ./tool/ci/web.sh`, `shell: bash`. Выполнен.
- DoD 7 — засчитан по D-32: run 37301435314 на `51eb041`, раннер `yuv-self-hosted`; упал camera smoke, цели `--wasm`
  после него в workflow не запускались (на Mac локально прошли, DoD 3).
- DoD 8 — перенесён по D-32 в отдельную карточку.
- Architect Decision: шаги `web.sh` совпадают с `web.ps1` (dry-run и проверка WASM-ассетов, сборка emsdk 3.1.74 и
  `git diff --exit-code`, матрица 9 + 5 источников и 64 случая, reference `--profile`, camera smoke с fake media, три
  цели `--wasm`); проверка major-версий Chrome/драйвера роняет прогон (п. 4); `chmod 644` до dry-run и после сборки
  (п. 5); `drive_web` идёт через `drive.sh` с критерием `All tests passed`. Ошибка матрицы теперь роняет скрипт:
  `targets_output="$(assert_web_source_matrix)"` под `set -e`, а не process substitution.
- Scope и Constraints: изменены только `tool/ci/web.sh`, `ci-web.yml`, `AGENTS.md`, карточка и `todo.md`; `web.ps1`,
  `drive.*`, `tool/wasm/**`, `assets/wasm/**`, `src/**`, `lib/**`, `example/**` не тронуты.

Пробел отчёта, закрыт Reviewer текстом (п. 6 Architect Decision требовал от Executor предложить текст для `MACHINES.md`
и «Окружения» в `todo.md`) — предложение ниже, решение за Engineer:

> Mac (`yuv-self-hosted`) выполняет Web CI (`ci-web.yml`, `bash tool/ci/web.sh`): Chrome из `/Applications/Google
> Chrome.app`, драйвер `~/bin/chromedriver` той же major-версии, emsdk 3.1.74 в `~/storage/emsdk-3.1.74` (тег `3.1.74`;
> `master` требует Python 3.10, на Mac 3.9.6). Обновление Chrome без драйвера роняет Web CI. Windows-прогон `web.ps1` —
> локальная проба Executor.

Блокирующих замечаний нет.

Recommendations:

- Новая карточка по D-32: camera smoke на Mac. По стеку `camera_controller.dart:361` (`set value`) срабатывает после
  `controller.dispose()` из teardown; вероятная гонка теста на более медленном Mac (на Windows тест зелёный). Пока она
  не закрыта, `CI Web` и `ci/all` красные.
- Текст для `MACHINES.md` / «Окружения» — выше.
