# CI 1 — Запуск CI по тегам `ci/<набор>/<метка>`
**Status:** REVIEW · **Tier:** T2 · **Owner:** Executor (T2) · **Depends On:** — · **Probe:** none

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

6. **Документы после чистки `AGENTS.md`** (Orchestrator, 03.10.2026, `dev` после CLEAN 4). `AGENTS.md` переписан:
   раздел «CI» уже описывает D-23, таблица «путь → ключи» заменена ссылкой на `scope_guard.sh`. Документная часть
   решений 4–5 для `AGENTS.md` сводится к проверке: после перевода workflow убрать из строки «Автозапуска нет»
   оговорку «workflow переводятся на теги в CI 1». `todo.md` — как в решении 5.
7. **`scope_guard.sh` сравнивает с `origin/release/0.4.2`** — ветка прошлого цикла. Заменить базу на `dev`
   (`git merge-base dev HEAD`); сообщение об ошибке — тоже. Проверка: на ветке пула `bash tool/ci/scope_guard.sh` —
   exit 0; на временной ветке `vm/scope-check` с изменённым `lib/` файлом — exit 1 с сообщением про `vm example`
   (ветку удалить).
8. **Lock example на Linux.** В джобе `linux-native-smoke` `flutter create --platforms=linux .` пересобирает
   `example/pubspec.lock` (CI 2: `camera` 0.11.0+2 → 0.11.4), и Linux проверяет другие версии, чем остальные
   платформы. Проверить на Linux VM `flutter create --platforms=linux --no-pub .` + `flutter pub get`: если lock не
   меняется (`git diff --exit-code example/pubspec.lock`) — так и сделать в `ci.yml`; если меняется — в отчёт
   причину, `ci.yml` не менять.

#### Scope
- `.github/workflows/ci*.yml` (9 файлов, `on.push`; в `ci.yml` — ещё шаг `flutter create` по решению 8).
- `tool/ci/scope_guard.sh` (решение 7).
- `AGENTS.md` (разделы решения 4), `todo.md` (правило 4, «CI и проверки»).

#### Constraints
- Джобы, runner'ы, шаги и `tool/ci/*` не трогать, кроме решений 7–8.
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

- [ ] Решение 7: `scope_guard.sh` — база `dev`, оба прогона проверки в отчёте.
- [ ] Решение 8: результат проверки lock на Linux VM в отчёте; `ci.yml` — по результату.

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

2026-10-03

- Workflow head: `41f444f3d25cb8c94b15abdd3657e4feaf26c243` (`all/PAR-CI`); D-23 leaves only the two tag patterns in
  every workflow and removes the release-specific concurrency condition. `git diff --check` and the tags-only
  assertion for all nine workflow files passed. `actionlint` is unavailable on this machine.
- Negative control: pushed `all/PAR-CI` at this SHA; `gh run list --commit 41f444f3d25cb8c94b15abdd3657e4feaf26c243`
  returned `[]` (exit 0).
- Original `ci/all/CI-1` is terminal: [Android](https://github.com/Anfet/yuv_ffi/actions/runs/37058238085),
  [Example](https://github.com/Anfet/yuv_ffi/actions/runs/37058238031),
  [macOS](https://github.com/Anfet/yuv_ffi/actions/runs/37058238034),
  [Windows](https://github.com/Anfet/yuv_ffi/actions/runs/37058237987),
  [smoke](https://github.com/Anfet/yuv_ffi/actions/runs/37058238180),
  [iOS](https://github.com/Anfet/yuv_ffi/actions/runs/37058238074), and
  [Web](https://github.com/Anfet/yuv_ffi/actions/runs/37058238161) succeeded. [VM](https://github.com/Anfet/yuv_ffi/actions/runs/37058238047)
  failed only in the removed Flutter 3.38 matrix (`filterQuality` unavailable); [Linux](https://github.com/Anfet/yuv_ffi/actions/runs/37058238078)
  failed at `camera_capture_native_test.dart` because the `camera` plugin has no Linux implementation. Neither is a
  tag-routing failure.
- `ci/smoke/CI-1-2` at the current SHA created exactly one workflow and succeeded:
  [CI smoke 37134018981](https://github.com/Anfet/yuv_ffi/actions/runs/37134018981).
- `scope_guard.sh`: `all/PAR-CI` passed (exit 0); a temporary `vm/scope-check` branch with only a `lib/` fixture
  failed as required (exit 1): `does not cover vm example required by lib/.scope_guard_ci1`. Its base is now
  `git merge-base dev HEAD`.
- Linux lock check used an isolated clone with Flutter 3.44.9. After `flutter create --platforms=linux --no-pub .`
  and `flutter pub get`, `example/pubspec.lock` changed (66 additions, 66 deletions). Therefore `ci.yml` keeps the
  existing `flutter create --platforms=linux .` step; `--no-pub` does not preserve the lock once dependencies resolve.
- Local validation passed: `tool/ci/smoke.ps1`; `tool/ci/vm.ps1` (616/616); `tool/ci/windows.ps1`;
  `tool/ci/web.ps1` (63 integration, 119 reference, camera smoke); `tool/ci/example.ps1`; and
  `tool/ci/android.ps1` (native runtime, camera, presenter shader, probe, shader probe on `emulator-5554`).
- After all run links were recorded, removed from origin and locally: `ci/all/CI-1`, `ci/smoke/CI-1`, and
  `ci/smoke/CI-1-2` (cleanup exit 0).
#### Review

2026-10-03 — Reviewer: **принято**, кроме причины в решении 8 (исправлена ниже).

- Workflow: все 9 файлов разобраны YAML-парсером — в `on` только `push.tags` (`ci/all/**`, `ci/<name>/**`) и
  `workflow_dispatch`; `branches`, `paths-ignore` и особый `concurrency` для `release/**` убраны.
- Запуски (`gh run list --commit`): `af895ae` — ровно 9 push-run от `ci/all/CI-1` и один `CI smoke` от
  `ci/smoke/CI-1`; `41f444f` — только `CI smoke` от `ci/smoke/CI-1-2`, success; `ef4c8f3`, `b124f1f`, `7540343`
  (голова `origin/all/PAR-CI`) — `[]`. Причины красных подтверждены логами: VM — только `vm (3.38.10)`,
  `filterQuality` не определён; Linux — `linux-native-smoke`, `camera_capture_native_test.dart:24`.
- Тегов `ci/*` нет ни в origin (`git ls-remote --tags`), ни локально.
- `scope_guard.sh` (во временном клоне): `all/PAR-CI` — exit 0; `vm/scope-check` от `dev` с файлом в `lib/` —
  exit 1, `does not cover vm example required by lib/...`.
- Документы: оговорка из строки «Автозапуска нет» в `AGENTS.md` убрана; `ci/**` в `AGENTS.md`, `todo.md`,
  `.github/` — только в D-9.
- **Решение 8 — причина в отчёте неверна.** Lock меняет не `pub get`, а сам `flutter create`: даже с `--no-pub` он
  перезаписывает `example/pubspec.lock` шаблонным (53 строки вместо 552), и `pub get` затем резолвит всё заново.
  Проверено на Windows, Flutter 3.44.9 (lock от платформы не зависит): `create --no-pub` + `pub get` — 66/66
  строк; `create --no-pub`, затем `git checkout -- pubspec.lock`, затем `pub get` — lock без изменений. По
  карточке `ci.yml` верно не изменён; восстановление lock между `create` и `pub get` — вне вариантов решения 8,
  выбор за Engineer (дополнить CI 1 или отдельной карточкой).
- **Решение 8 доделано по команде Engineer** (03.10.2026): в `ci.yml` — `flutter create --platforms=linux --no-pub .`,
  `git checkout -- pubspec.lock`, `flutter pub get`, `git diff --exit-code pubspec.lock`. Тег `ci/linux/CI-1-3` на
  `a08c007` запустил только `CI`: [run 37146614596](https://github.com/Anfet/yuv_ffi/actions/runs/37146614596) —
  `linux-native-smoke` и `bindings-regeneration` success, lock не изменился. Тег удалён.
