# CI 1 — Запуск CI по тегам `ci/<набор>/<метка>`
**Status:** BLOCKED · **Tier:** T2 · **Owner:** CLEAN 4 · **Depends On:** этап 6 · **Probe:** none

#### Goal
Контрольный CI сейчас запускается push'ем ветки `ci/<пул>` на точный SHA `dev` (D-9, D-18): ветки копятся на
origin (`ci/stage2-probes`, `ci/stage3-clean`, `ci/STAGE3-SPM-apple`), их можно сдвинуть, для повтора их
пересоздают, и запускается всегда весь набор из 9 workflow. Тег — неизменный указатель на SHA. Задача: заменить
ветки `ci/**` тегами вида `ci/<набор>/<метка>`, где набор — `all` или одна платформа (D-20), и убрать
автозапуск: CI запускается только тегом или вручную (D-23, решение 5).

Параллельная задача: этапы не блокирует. Отдельный пул `PAR-CI`. Ветка пула идёт от `dev` `ffc607b`, поэтому
тег `ci/all/CI-1` из DoD заодно служит отложенным post-merge CI этапов 4–5 (в том числе macOS и iOS).

#### Architect Decision
1. **Схема тега** `ci/<набор>/<метка>`:
   - `<набор>` — `all` (все workflow) или имя платформы: `vm`, `windows`, `macos`, `ios`, `android`, `web`,
     `example`, `smoke`, `linux`. Имя совпадает с `ci-<name>.yml` и ключом `scope_guard.sh`; `linux` — это
     `ci.yml` целиком (`linux-native-smoke` и `bindings-regeneration`).
   - `<метка>` — ID пула или задачи, при повторе — с номером: `STAGE5-DEVICE`, `APPLE-1-2`.
   - Несколько платформ на одном SHA — несколько тегов. Групп (`apple` и т. п.) нет.
2. **Триггеры.** В каждом из 9 workflow `on.push`:
   ```yaml
   on:
     push:
       branches:
         - "release/**"
         - main
       tags:
         - "ci/all/**"
         - "ci/<name>/**"
       paths-ignore: ["**/*.md", "doc/**", "tasks/**"]
     workflow_dispatch:
   ```
   `"ci/**"` из `branches` убирается. `paths-ignore` GitHub к тегам не применяет — тег запускает свой набор всегда,
   это и нужно для явного запроса. `workflow_dispatch` (и входы `ci.yml`) не меняются. `concurrency` не меняется:
   у каждого тега своя группа `${{ github.ref }}`.
3. **Релизный тег** (`v*`) CI не запускает: он ставится на уже проверенный SHA `release/**`.
4. **Документы.**
   - `AGENTS.md`, «CI соглашения»: триггеры — `release/**`, `main` и теги `ci/<набор>/<метка>`; пункт про ветку
     `ci/**` для задач, меняющих workflow, — тег на коммит ветки задачи; строка `linux` таблицы ключей; строка Probes
     про `ci/<pool-id>` (стр. 57). Короткое правило: тег ставит Reviewer/Orchestrator на точный SHA, результат —
     ссылка на run в `COMPLETION.md`; теги `ci/*` удаляются пачкой в конце этапа (run при этом остаётся).
   - `todo.md`: правило 4, «CI и проверки» (триггеры, интеграция); D-20 уже записано Architect.
   - Старые ветки `ci/*` на origin удаляет Engineer — в задачу не входит.
5. **Только по тегам (D-23, добавлено Architect 02.10.2026 после первого прогона).** Автозапуска нет ни у одного
   workflow, включая Linux: локальные `tool/ci`-скрипты — основная проверка, CI ставится тегом там, где нужна
   платформа, которой нет под рукой.
   - В 9 workflow `on.push` — только `tags` (`ci/all/**`, `ci/<name>/**`); `branches` и `paths-ignore` убираются
     (к тегам `paths-ignore` не применяется). `workflow_dispatch` и его входы остаются. `concurrency` — без
     особого случая для `release/**`: у каждого тега своя группа.
   - Релизный гейт: перед тегом `v*` на SHA `release/<версия>` ставится `ci/all/<версия>`; выход — зелёный набор
     или явное решение Engineer.
   - `AGENTS.md`: «CI соглашения» — строка триггеров (push в `release/**` и `main` CI не запускает), пункт про
     `paths-ignore` и про `concurrency` на `release/**`, строка `linux` в таблице ключей; «Probes» — без изменений.
   - `todo.md`: «CI и проверки» → «Триггеры (D-23)»; правило 4 — ссылка на D-23; решение D-23 записано Architect.

#### Scope
- `.github/workflows/ci*.yml` (9 файлов, только `on.push`).
- `AGENTS.md` (разделы решения 4), `todo.md` (правило 4, «CI и проверки»).

#### Constraints
- Джобы, runner'ы, шаги и `tool/ci/*` не трогать.
- Push тегов `ci/*/CI-1` и `ci/*/CI-1-<n>` и ветки пула в origin разрешён этой карточкой; другие теги и ветки — нет.

#### Definition of Done
- [ ] 9 workflow: в `on.push` только `tags` — `ci/all/**` и `ci/<своё имя>/**`; `branches` и `paths-ignore` нет;
      `workflow_dispatch` есть (решение 5).
- [ ] Тег `ci/smoke/CI-1` на коммит ветки пула запускает ровно один workflow (`CI smoke`), и он зелёный.
- [ ] Тег `ci/all/CI-1` на тот же коммит запускает все 9 workflow (результаты — ссылками в отчёт; красный прогон
      разбирается, только если причина — триггер, а не платформа).
- [ ] Негативный контроль: push ветки пула `all/PAR-CI` не запускает ни одного workflow.
- [ ] `AGENTS.md` и `todo.md` по решению 4; поиск `ci/\*\*` в `AGENTS.md`, `todo.md`, `.github/` находит только
      описание прошлой схемы в D-9/D-18.
- [ ] После решения 5 на новом коммите ветки: push ветки не запускает ни одного workflow; тег `ci/smoke/CI-1-2`
      запускает ровно `CI smoke`, и он зелёный. Полный `ci/all` повторно не нужен.
- [ ] Красный Linux в `ci/all/CI-1` (`camera_capture_native_test.dart`: у плагина `camera` нет Linux-реализации) —
      причина в платформе, не в триггере: в отчёт ссылкой; карточку отказа заводит Orchestrator, Executor не чинит.
- [ ] Тестовые теги `ci/*/CI-1` и `ci/*/CI-1-<n>` удалены из origin после записи ссылок.

#### Validation
Ключи: `.github/workflows/ci.yml`, `ci-smoke.yml` → `all`. Ветка пула — `all/PAR-CI`. Локально триггеры не
проверить; доказательство — запуски из DoD:

- `gh run list --commit <sha> --json workflowName,event,headBranch,status,conclusion` после каждого push
  (тег — `event: push`, `headBranch` — имя тега).
- `actionlint` по изменённым workflow, если доступен; иначе `gh workflow view` каждого после push тега.

#### Executor Report
2026-10-02

- Head with workflow change: `af895ae4723e55d66d307a9b71d8b37ab4aa77be` (`all/PAR-CI`).
- `git diff --check` — PASS. `actionlint` is unavailable on this machine.
- Negative control: pushing `all/PAR-CI` created no workflows (`gh run list --commit af895ae...` returned `[]`).
- `ci/smoke/CI-1` created exactly `CI smoke` and passed: [run 37058181777](https://github.com/Anfet/yuv_ffi/actions/runs/37058181777).
- `ci/all/CI-1` created exactly nine push workflows on the same SHA: [Android 37058238085](https://github.com/Anfet/yuv_ffi/actions/runs/37058238085), [VM 37058238047](https://github.com/Anfet/yuv_ffi/actions/runs/37058238047), [Example 37058238031](https://github.com/Anfet/yuv_ffi/actions/runs/37058238031), [macOS 37058238034](https://github.com/Anfet/yuv_ffi/actions/runs/37058238034), [Windows 37058237987](https://github.com/Anfet/yuv_ffi/actions/runs/37058237987), [smoke 37058238180](https://github.com/Anfet/yuv_ffi/actions/runs/37058238180), [iOS 37058238074](https://github.com/Anfet/yuv_ffi/actions/runs/37058238074), [Linux 37058238078](https://github.com/Anfet/yuv_ffi/actions/runs/37058238078), [Web 37058238161](https://github.com/Anfet/yuv_ffi/actions/runs/37058238161). At the recorded check, Android/Linux/macOS were running and the other six were queued.
- Test tags remain on origin until terminal results are recorded, then both `ci/smoke/CI-1` and `ci/all/CI-1` must be deleted before `REVIEW`.

- **Частичное слияние** (Reviewer, 02.10.2026, по команде Engineer): решения 1–4 влиты в `dev` на `fda538d`; CI
  перенесён после этапа 6. Итоги `ci/all/CI-1` к моменту слияния: Android, iOS, macOS, Windows, Web зелёные; Linux
  красный — платформа, не триггер (карточка CI 2); VM, smoke, Example ещё шли. Остаток пула: дописать итоги,
  решение 5 (D-23), повторный негативный контроль и `ci/smoke/CI-1-2`, удалить тестовые теги. Продолжать в ветке
  `all/PAR-CI` от актуального `dev`.
#### Review
