# CI 1 — Запуск CI по тегам `ci/<набор>/<метка>`
**Status:** TODO · **Tier:** T2 · **Owner:** — · **Depends On:** — · **Probe:** none

#### Goal
Контрольный CI сейчас запускается push'ем ветки `ci/<пул>` на точный SHA `dev` (D-9, D-18): ветки копятся на
origin (`ci/stage2-probes`, `ci/stage3-clean`, `ci/STAGE3-SPM-apple`), их можно сдвинуть, для повтора их
пересоздают, и запускается всегда весь набор из 9 workflow. Тег — неизменный указатель на SHA. Задача: заменить
ветки `ci/**` тегами вида `ci/<набор>/<метка>`, где набор — `all` или одна платформа (D-20).

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

#### Scope
- `.github/workflows/ci*.yml` (9 файлов, только `on.push`).
- `AGENTS.md` (разделы решения 4), `todo.md` (правило 4, «CI и проверки»).

#### Constraints
- Джобы, runner'ы, шаги и `tool/ci/*` не трогать.
- Push тегов `ci/*/CI-1` и ветки пула в origin разрешён этой карточкой; другие теги и ветки — нет.

#### Definition of Done
- [ ] 9 workflow: `branches` — `release/**`, `main`; `tags` — `ci/all/**` и `ci/<своё имя>/**`.
- [ ] Тег `ci/smoke/CI-1` на коммит ветки пула запускает ровно один workflow (`CI smoke`), и он зелёный.
- [ ] Тег `ci/all/CI-1` на тот же коммит запускает все 9 workflow (результаты — ссылками в отчёт; красный прогон
      разбирается, только если причина — триггер, а не платформа).
- [ ] Негативный контроль: push ветки пула `all/PAR-CI` не запускает ни одного workflow.
- [ ] `AGENTS.md` и `todo.md` по решению 4; поиск `ci/\*\*` в `AGENTS.md`, `todo.md`, `.github/` находит только
      описание прошлой схемы в D-9/D-18.
- [ ] Тестовые теги `ci/*/CI-1` удалены из origin после записи ссылок.

#### Validation
Ключи: `.github/workflows/ci.yml`, `ci-smoke.yml` → `all`. Ветка пула — `all/PAR-CI`. Локально триггеры не
проверить; доказательство — запуски из DoD:

- `gh run list --commit <sha> --json workflowName,event,headBranch,status,conclusion` после каждого push
  (тег — `event: push`, `headBranch` — имя тега).
- `actionlint` по изменённым workflow, если доступен; иначе `gh workflow view` каждого после push тега.

#### Executor Report
#### Review
