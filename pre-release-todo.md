# yuv_ffi 0.4.2 — предрелизный цикл RA

Источник: предрелизный аудит 27.09.2026 (HEAD `9b41cb5`), повторная сверка 28.09.2026 на `db42681`. Карточки RA заменяют PRE-00…07 из `doc/archive/perf/prerelease-todo.md`. Архитектор — Claude Opus (T1). Engineer разрешил довести весь цикл до RA-50 по зависимостям; отдельный pub.dev publish не входит в задачу.

**Объём релиза заморожен.** VIEW-00…03 и PACK-00…01D приняты. С начала цикла RA в `lib/`, `src/`, `example/lib/` не добавляется новая функциональность; любое новое требование — отдельной карточкой после решения Engineer.

## CI runner policy

Engineer установил правило: jobs проекта не должны выполняться на GitHub-hosted runners; исключение — один Linux job. GitHub API на 28.09.2026 показывает онлайн `dev.working` (`Windows`, `X64`) и `yuv-self-hosted` (`macOS`, `X64`). Linux job `linux-native-smoke` объединяет Linux packaging/runtime smoke и native sanitizer suite; это единственная job, оставленная на GitHub-hosted `ubuntu-latest`. Остальные jobs используют self-hosted runners. WSL не устанавливался: Windows runner нужен для Android и Web/WASM, а пользователь указал, что WSL/Hyper-V может затронуть режим гибернации; менять системную конфигурацию нельзя без его решения.

Текущая маршрутизация: macOS native, iOS Simulator и bindings regeneration — `yuv-self-hosted`; Windows native, Flutter VM matrix, Android x86_64 emulator, Web/WASM и example analyze/build — `dev.working`; Linux smoke плюс sanitizer — единственная hosted Linux job. На Windows runner доступны Android SDK `D:\.important\android-sdk`, x86_64 API 35 AVD `Tablet` (конфигурация `Pixel_Tablet.avd`), Chrome `154.0.8037.58`, ChromeDriver `D:\.projects\.tools\chromedriver-win64\chromedriver.exe` (`154.0.8037.57`) и Git Bash `D:\.important\Git\bin\bash.exe`. Установленный глобально emsdk `5.0.1` не используется для RA-40; runner ставит точный `3.1.74` в `D:\.projects\.tools\emsdk-3.1.74`.

## Current board — 28.09.2026

**Candidate:** `1ef71b68540c7133f2e223cd0320b2cb155ecbd5` is pushed to `origin/release/0.4.2`. CI run `36453924374`: `linux-native-smoke`, `ios-native-build`, `macos-native-smoke`, and `bindings-regeneration` passed; Web integration is running; Android, Windows, VM matrix, and example jobs are queued. RA-25 both ABI gates passed; full device/host evidence is archived locally and awaits next commit.

| State | Card | What is verified now | Next action / blocker |
| --- | --- | --- | --- |
| **IN PROGRESS · Terra** | **RA-26** | Balanced + AC are valid. Dirty Windows and Pixel diagnostics passed 24/24 but `sourceVerified=false`, so neither is comparison evidence. Strict tag-package provenance support is implemented; focused tests passed 10/10 and PowerShell parser is clean. | Commit/push the provenance fix, then run validation-only positive/negative controls in the clean baseline app worktree. Start timing only after app SHA and tag package revision/path are proven. |
| **EVIDENCE READY · Terra** | **RA-25** | Both Pixel 3 ABI gates passed. armv7 APK SHA `6543c931…b4e243`; arm64 SHA `6a175d1d…11980f`. Each has smoke/probe PASS, 1188 cases, APK ABI/library, installed `primaryCpuAbi`, and strict host/device result. Full reports and raw host/logcat evidence are archived under `doc/archive/release-0.4.2/ra25-pixel3/`, awaiting commit. | Commit the archived reports with the next status update; independent T1 review remains before final acceptance. |
| **IN CI · Terra** | **RA-22** | Workflow `36453924374`: `linux-native-smoke`, `ios-native-build`, and `macos-native-smoke` passed; Android is queued. Local `drive.sh` controls reject exit 0 without marker and exit 7 with marker. | Confirm Android and all 4 native jobs on the shared SHA, then run remote corrupted-golden control and revert. |
| **WAITING FOR WINDOWS JOB** | **RA-23** | Workflow `36453924374` is active; Windows, VM matrix, and example jobs remain queued. Workflow and local Windows root suite are prepared. | Confirm Windows job is green on the shared SHA. |
| **WAITING FOR WINDOWS JOB · Terra** | **RA-40** | Workflow `36453924374` is active; Windows rebuild comparison remains queued. Two isolated emsdk 3.1.74 builds matched committed JS/WASM assets and each other byte-for-byte. | Confirm workflow rebuild comparison on the shared SHA. |
| **IN CI · Terra** | **RA-41** | Workflow `36453924374` Web integration is running. Local Web gate passed 13/13 targets and reference matrix passed 119/119 with zero mismatches. | Confirm Web CI on the shared SHA, then run remote corrupted-WASM negative control and revert. |
| **REVIEW AT END** | **RA-21** | Local 1188-case oracle/probe and root checks passed; Web seed issue is resolved under RA-41. | Independent T1 review at the end, as requested. |
| **QUEUED** | **RA-19** | Documentation cleanup is ready by scope. | After RA-22, RA-23, and RA-41 settle; it edits workflow comments, so it must precede the final CI run. |
| **QUEUED** | **RA-27** | Probe policy decision is ready. | After RA-26 measurements are accepted. |
| **QUEUED** | **RA-18** | Changelog structure is approved. | After performance/device evidence and other release changes are final. |
| **FINAL GATE** | **RA-50** | Not started. | One green final SHA, clean package dry-run/allowlist, synchronized versions, report. No tag or pub.dev publish. |

**Recently completed local checks:** `flutter analyze --no-fatal-infos lib test` clean; full root suite 711 passed/1 skipped (native DLL was supplied from the existing workspace build path; this is not a fresh CI-style native build); local Web dynamic gate 13/13 and reference matrix 119/119; emsdk 3.1.74 reproducibility; RA-22 helper negative controls. `flutter pub publish --dry-run` last reported one warning only because the worktree was dirty, plus the expected version hint; rerun after commit. `tool/bench/` is user-owned and must remain untouched/uncommitted.

**Orchestration:** Terra (`ra26_windows_collection`) owns candidate integration and the next RA-26/RA-25 runs. Pixel profile diagnostic is complete. No product-code implementation is assigned to the coordinator; current work is delegated, status tracking, integration, and final acceptance.

**Исторический срез до последних push: commit `8af210e` плюс тогдашняя рабочая копия:** RA-05 ранее прошёл на Flutter 3.38.10 и 3.44.9 в run `36413754181`. RA-02 dry-run: 0 warnings, allowlist соблюдён, архив 974 KB; публикации не было. В run `36427394808` прошли Linux smoke/sanitizer, macOS native smoke, iOS simulator/device build и smoke, bindings regeneration и example analyze/build 3.41.0. Windows root tests выявили две runner-specific проблемы: test provenance не искал DLL в PATH; probe source/copy различались только CRLF/LF. В рабочей копии исправлен Windows PATH lookup, добавлен `.gitattributes` LF для synced probe-файлов; локально `flutter analyze --no-fatal-infos lib test` чистый, полный `flutter test` прошёл 703 теста с собранной DLL в PATH. Commit и CI rerun ожидаются. Android job в `36427394808` ещё не стартовал; предыдущий run собрал arm64/armv7 APK, а новое имя API 35 x86_64 AVD `Tablet` ждёт подтверждения CI. RA-21 oracle совпал на 1188/1188 случаях и локальный Windows probe прошёл; требуется финальное независимое ревью. На свежих emsdk 3.1.74 assets Web probe завершился exit 1 с минимум 20 gray I420/NV12 mismatches (доказательство в `doc/archive/release-0.4.2/web-probe-evidence.md`); RA-41 требует решения Architect. Pixel 3 profile smoke и probe 1188/1188 прошли, APK arm64/armv7 собраны; release assertions остаются заблокированы ограничением Flutter Driver, см. RA-25. Runner API показывает `dev.working` (Windows x64) и `yuv-self-hosted` (macOS x64) online. Только Linux smoke/sanitizer job использует GitHub-hosted runner; Android, Web и Windows jobs — self-hosted Windows, iOS/macOS/bindings — self-hosted Mac.

**Snapshot на HEAD `d8d8d48` от 28.09.2026:** CI-run `36431067534` был отменён при зависании browser fake-module tests до старта Windows job. Детальные актуальные статусы находятся в Current board выше; старые сведения далее по документу сохранены как история, если помечены историческими.

## Решения Engineer

| ID | Status | Вопрос | Рекомендация Architect |
| --- | --- | --- | --- |
| D-1 | DECIDED 28.09.2026 | Версия релиза при смене умолчания layout (PACK-01B). | **0.4.2.** Последняя опубликованная неотозванная версия — 0.2.4, 0.4.0 отозвана, поэтому 0.5.0 ничего не даёт. Смена умолчания описывается как **Behavior change** в CHANGELOG и отдельной строкой в таблице миграции с 0.2.4 в README: фабрики с `planes:` теперь упаковывают плоскости, для старого поведения — `layout: YuvPlaneLayout.preserve`. |

## Full Card Registry

Этот реестр сохраняет владельца, зависимости и причину статуса карточек. Быстрый актуальный статус — в таблице Current board выше.

| Done | ID | Status | Tier | Owner | Depends On | Summary |
| --- | --- | --- | --- | --- | --- | --- |
| [x] | RA-05 | DONE | T3 | Luna | — | Обе матричные Analyze/Test jobs прошли на Flutter 3.38.10 и 3.44.9 (run `36413754181`); legacy info остались видимыми, но не блокируют. |
| [x] | RA-06 | DONE | T3 | Luna | — | Гигиена CI подтверждена: checkout использует разрешённую `@v4`, ARMv7 APK build и проверка ABI зелёные, Markdown-only push не запускает workflow. Предупреждение Node 20 остаётся, так как allowlist блокирует `@v5`. |
| [x] | RA-08 | DONE | T3 | Luna | — | Удалены 10 сырых `*.log` и 2 `*.nv12`; CI dry-run проверка package assets прошла с 0 warnings. |
| [x] | RA-02 | DONE | T3 | — | RA-01, RA-08 | Dry-run на `e66751e`: 0 warnings, 1 допустимая hint, allowlist совпал, архив 974 KB; публикации в pub.dev нет. |
| [x] | RA-04 | DONE | T3 | — | RA-01, RA-05, RA-06 | 10 файлов переименованы; analyze чистый, 703 теста прошли; run `36415310682` прошёл во всех jobs, кроме независимого WASM rebuild gate RA-40. |
| [x] | RA-16 | DONE | T3 | — | RA-01, RA-04 | README и example-комментарии очищены по DOC-RULES; `flutter analyze` чистый, 71 example test пройден. Сохранены только CI runtime markers/messages и термины `pre-screen`/`pre-injection`, описывающие состояние. |
| [ ] | RA-19 | TODO | T3 | — | RA-22, RA-23, RA-41 | Вычистить служебные README (`tool/wasm`, `assets/wasm`, `test_native`) и комментарии CI от номеров задач после закрытия зависимостей. |
| [ ] | RA-21 | REVIEW_AT_END | T2 | — | RA-06, RA-08, RA-13 | Локальные DoD пройдены: 1188 оракулов/проб на Windows, coverage/layout/copy sync. Доказательства ждут финального независимого ревью в конце цикла по указанию Engineer; Web-проба перенесена в RA-41. |
| [ ] | RA-26 | IN_PROGRESS | T2 | Terra | RA-21 | Balanced/AC подтверждены; JIT диагностика нестабильна. Dirty Windows smoke и Pixel profile прошли 24/24, но `sourceVerified=false`: это не baseline/comparison evidence. Current runner validates only app SHA, not the package resolved by baseline `package_config`; strict override/path/revision validation and tests are now in progress. Only after they pass: commit/push harness fix, run clean 0.4.0/HEAD Release comparisons and archive, then Pixel comparison. |
| [ ] | RA-27 | TODO | T3 | — | RA-26 | Записать в AGENTS.md правило проб для задач разработки (Windows у исполнителя, Pixel 3 на ревью) и поле `Probe` в шаблон карточки. |
| [ ] | RA-22 | IN_CI | T2 | Terra | RA-04, RA-06, RA-21 | Workflow `36453924374`: Linux, iOS and macOS native jobs passed; Android queued. Need green evidence for all four native jobs, then remote corrupted-golden run/revert. |
| [ ] | RA-23 | WAITING_FOR_WINDOWS_JOB | T2 | — | RA-06, RA-21, RA-22 | Workflow `36453924374` is active; Windows, VM matrix, example jobs queued. Need a green Windows job on the shared SHA. |
| [ ] | RA-25 | EVIDENCE_READY | T2 | Terra | RA-13, RA-21, RA-26 | Both ABI strict host/device gates passed; armv7 APK SHA `6543c931…b4e243`, arm64 `6a175d1d…11980f`. Full README, host stdout/stderr and final arm64 logcat record are under `doc/archive/release-0.4.2/ra25-pixel3/`; commit pending. Independent T1 acceptance remains. |
| [ ] | RA-40 | WAITING_FOR_WINDOWS_JOB | T2 | Terra | RA-06, RA-08, RA-13 | Workflow `36453924374` is active; Windows rebuild comparison is queued. Two isolated emsdk 3.1.74 builds and committed assets match: JS `DC5E08EE…F39D5`, WASM `BAD2FC75…1D08F`. |
| [ ] | RA-41 | IN_CI | T2 | Terra | RA-04, RA-21, RA-22, RA-40 | Workflow `36453924374` Web integration is running. Local dynamic 13/13 and reference 119/119 passed; remote negative control remains. |
| [ ] | RA-18 | TODO | T2 | — | все RA кроме RA-50 | Финальный CHANGELOG 0.4.2 вместо черновика: фактические изменения, новый API, известные ограничения. |
| [ ] | RA-50 | TODO | T2 | — | все RA | Не начат: ждёт закрытия предыдущих RA и финального CI на одном SHA. Тег и публикация — Engineer; pub.dev publish не входит в эту работу. |

Дополнение к разбиению от 28.09.2026: RA-10, RA-11, RA-12, RA-13, RA-15 и RA-17 выполняются параллельно с RA-01. Их области — Dart/C комментарии, test_native комментарии и README; RA-01 перемещает файлы, меняет ссылки в orchestration Markdown и одну ссылку в CHANGELOG. Пересечений по изменяемым строкам нет. Валидация каждой карточки остаётся обязательной. RA-16 остаётся после RA-01 и RA-04 из-за пересечения с перемещаемыми example integration tests. После группы продолжаем по зависимостям таблицы.

Ревью: T3 → T2; T2 → T1 (предпочтительно другой провайдер, чем исполнитель); RA-50 — T1 + Engineer. Принятые карточки переносятся в `COMPLETION.md` по протоколу; этот файл содержит только текущую работу цикла.

---

## DOC-RULES — общее решение Architect для RA-10…RA-19

1. Удалить: номера задач и ревью (`YUV-`, `REL-`, `BGRA-`, `AUD-`, `OPT-`, `BLUR-`, `CVT-`, `VIEW-`, `MEAS-`, `PERF-`, `PRE-`, `WAIT-`, `PATCH-`, `F-0xx`), ссылки на `todo*.md`, `COMPLETION.md`, `completed.md`, `doc/perf`, `doc/archive`, `doc/archive/api-abi-0.4-design.md`, «section N», «Q1», пересказ истории («used to», «earlier revisions», «pre-…», «was removed in …», «independent review showed»).
2. Оставить и при необходимости переформулировать: что делает символ, параметры, возврат, исключения, побочные эффекты (revision, мутация, владение памятью), платформенные различия, ограничения, неочевидное «почему» — без ссылки на задачу.
3. Публичный dartdoc — по Effective Dart: первая фраза — краткое описание; `Throws …` для документированных ошибок; ссылки `[Symbol]` только на экспортируемые символы.
4. Комментарий, который после чистки ничего не объясняет, удаляется целиком. Бесполезные `// ignore:` внутри dartdoc-блоков удаляются только если анализ остаётся чистым.
5. Код, сигнатуры, строки сообщений об ошибках, имена символов не меняются. Если комментарий противоречит коду — код не трогать, записать расхождение в Executor Report (ARCHITECT_REQUIRED, если это меняет контракт).
6. Язык комментариев — английский (как сейчас в коде).

Проверка для каждой DOC-задачи: регэксп из п.1 по файлам scope даёт 0 совпадений (исключения перечислить в отчёте с причиной); `git diff` содержит только строки комментариев.

---

### RA-05 — Зелёная джоба `analyze-and-test-vm (3.38.10)`
**Status:** DONE · **Tier:** T3 · **Owner:** Luna · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** — · **Rejection Count:** 0

#### Problem / Goal
Джоба падала на Flutter 3.38.10 из-за `deprecated_member_use_from_same_package`. Первопричина и итог проверки записаны в Executor Report ниже.

#### Architect Decision
`test/plane_row_copy_contract_test.dart` имеет `// ignore_for_file: deprecated_member_use_from_same_package`: тест намеренно проверяет внутренний транспорт, который ключуется устаревшим `YuvFileFormat`. На Flutter 3.38.10 этот же analyzer также сообщает о шести других намеренных same-package deprecation calls в legacy API и тестах; чтобы сохранить ограничение «не менять `lib/`», запускать `flutter analyze --no-fatal-infos lib test`. Warnings и errors остаются блокирующими; текущий Flutter 3.44.9 выводит для тех же файлов 0 info.

#### Constraints / Non-goals
Не менять `lib/`, не поднимать нижнюю границу SDK, не убирать 3.38.10 из матрицы. Если `flutter test` на 3.38.10 падает из-за реальной несовместимости пакета (а не теста) — ARCHITECT_REQUIRED с логом: это решение Engineer о границе `flutter: '>=3.38.0'`.

#### Definition of Done
- [x] Обе матричные джобы `analyze-and-test-vm` зелёные в CI-run `36413754181`
- [x] Нет изменений в `lib/`; устаревшее внутреннее использование остаётся видимым в CI, но analyzer info не валит только эту проверку

#### Validation / Testing
`flutter analyze --no-fatal-infos lib test`; ссылка на зелёный CI-run.

#### Executor Report
Добавлен `// ignore_for_file: deprecated_member_use_from_same_package` в `test/plane_row_copy_contract_test.dart`. CI run `36411031370` на Flutter 3.38.10 нашёл ещё шесть same-package deprecation infos в трёх legacy-файлах `lib/` и двух тестах; на 3.44.9 эти же info отсутствуют. Из-за запрета менять `lib/` шаг Analyze запускается с `--no-fatal-infos`; warnings и errors остаются блокирующими. Новый CI run `36413754181` подтвердил зелёные матричные Analyze/Test jobs на обеих версиях.

#### Review
Проверено по CI run `36413754181`: обе версии Flutter прошли Analyze и Test. Для 3.38.10 info остаются видимыми, но не блокируют анализ; ошибки и warnings по-прежнему блокируют.

---

### RA-06 — Гигиена CI
**Status:** DONE · **Tier:** T3 · **Owner:** Luna · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** — · **Rejection Count:** 0

#### Problem / Goal
- `android-armv7-runtime` падает в каждом run на `release/0.4.2` (11 из 11): `flutter drive` на ARM-трансляции эмулятора виснет и убивается `timeout` (exit 137). Джоба `continue-on-error`, поэтому ничего не доказывает, но красит страницу run и занимает около 25 мин.
- CI запускается на любой push, включая коммиты только в `todo.md`/`completed.md`; из последних 15 run на ветке 4 отменены из-за наложения.
- Предупреждение Node 20 для `actions/checkout@v4`.

#### Architect Decision
1. Удалить джобу `android-armv7-runtime` целиком. ARMv7 доказывается на физическом Pixel 3 (RA-25). Шаг `Verify ARMv7-only APK contents` перенести в `android-native-build` как отдельный шаг после сборки: `flutter build apk --debug --target=integration_test/native_app_runtime_smoke_test.dart --target-platform android-arm --split-per-abi` + та же проверка состава APK (сборку armv7 продолжаем проверять в CI, запуск — нет).
2. В начало workflow: `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }`.
3. В `on.push` и `on.pull_request`: `paths-ignore: ['**/*.md', 'doc/archive/**', 'doc/archive/perf/**']`. `README.md` и `CHANGELOG.md` тоже игнорируются — они проверяются финальным run RA-50.
4. Использовать `actions/checkout@v4`: репозиторий разрешает только эту версию. Обновление до `@v5` блокируется allowlist GitHub Actions. Другие actions не трогать; пока allowlist не изменён Engineer, предупреждение Node 20 для разрешённой версии документируется.

#### Constraints / Non-goals
Не менять шаги остальных джоб, кроме переноса проверки APK. Не делать другие джобы non-blocking.

#### Definition of Done
- [ ] В workflow нет `android-armv7-runtime` и нет `continue-on-error`
- [ ] Проверка состава armv7 APK выполняется в `android-native-build` и зелёная
- [ ] Коммит только в md не запускает CI (проверить пустым md-коммитом в отчёте)
- [ ] Нет ошибок allowlist для checkout; предупреждение Node 20 документировано, пока разрешён только `@v4`

#### Validation / Testing
YAML-парсинг локально; ссылка на CI-run.

#### Executor Report
Удалена джоба `android-armv7-runtime`; сборка ARMv7-only APK и проверка его ABI находятся в `android-native-build`. Добавлены отмена устаревших запусков и `paths-ignore`. `checkout@v5` блокируется allowlist репозитория, поэтому workflow использует разрешённый `@v4`; Node 20 warning остаётся видимым и не блокирует job. В CI run `36411031370` Android build и Verify ARMv7-only APK contents прошли. Markdown-only push `0ea4483` не создал новый run, что подтверждает `paths-ignore`.

#### Review
Поведение workflow и allowlist подтверждены; Android ARMv7 APK и ABI check прошли в CI. Node 20 warning принят как ограничение repo allowlist, поскольку разрешена только `checkout@v4`.

---

### RA-08 — Разблокировать `pub publish --dry-run`
**Status:** DONE · **Tier:** T3 · **Owner:** Luna · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** — · **Rejection Count:** 0

#### Problem / Goal
`wasm-web-integration` падает в каждом run на шаге `Verify published package contains committed WASM`: dry-run выходит с кодом 65 из-за предупреждения «10 checked-in files are ignored by a `.gitignore`» (логи `doc/archive/perf/results/blur0{1,2}_*/**/*.log`, коммиты `2285ca9`, `c115d78`). Из-за этого до пересборки WASM и Web-гейта джоба не доходит.

#### Architect Decision
Сырые логи — мусор, а не доказательство: 8 из 10 — дамп logcat рядом с одноимённым `.jsonl`, где лежат те же измерения; `host.log` пустой; `host-error.log` (479 байт) — ошибка неудачного запуска. Ни один md-файл на них не ссылается как на источник данных. Два кадра `*.nv12` (по 2,3 МБ) — сырой вывод BLUR-04; отчёт хранит их checksum, ссылок на файлы нет.

`git rm` (не в архив):
- `doc/archive/perf/results/blur01_raw/{yonly,yuv}/*.log`
- `doc/archive/perf/results/blur01_visual_raw/{rgb,yonly,yuv}/*.log`
- `doc/archive/perf/results/blur02_raw/{yonly,yuv}/*.log`
- `doc/archive/perf/results/blur02_control/mean_then_box/mean/*.log` (3 файла)
- `doc/archive/perf/results/blur04_raw/separable/20260926-014531-gaussian-separable.nv12`
- `doc/archive/perf/results/blur04_raw/yuv/20260926-014225-gaussian-yuv.nv12`

`.gitignore` не менять: `*.log` остаётся игнорируемым, чтобы логи больше не попадали в репозиторий. `.jsonl`/`.csv` не трогать.

#### Constraints / Non-goals
Не удалять `.jsonl`, `.csv`, `.md`. Не переписывать историю git.

#### Definition of Done
- [ ] В `git ls-files` нет ни одного `*.log` и `*.nv12`
- [ ] `flutter pub publish --dry-run` локально: предупреждения о gitignored-файлах нет
- [ ] В CI-run шаг `Verify published package contains committed WASM` зелёный. Следующее ожидаемое падение — `Rebuild and compare WASM artifacts` (устаревший WASM); его чинит RA-40, в этой карточке не исправлять.

#### Validation / Testing
Вывод dry-run и ссылка на run.

#### Executor Report
Удалены все 10 tracked `*.log` и 2 tracked `*.nv12`; проверка `git ls-files` по этим расширениям вывела пустой результат. `flutter pub publish --dry-run` после `30fff53` прошёл с 0 warnings (одна допустимая подсказка по версии). В CI run `36411031370` шаг `Verify published package contains committed WASM` также прошёл с 0 warnings и нашёл оба committed WASM assets; следующий rebuild step правильно обнаружил их устаревшее состояние (RA-40).

#### Review
Удаления соответствуют Architect Decision; `.jsonl`/`.csv` и `.gitignore` не менялись. Локальный dry-run и CI package gate прошли. Публикация пакета не выполнялась.

---


### RA-02 — Чистый архив пакета
**Status:** DONE · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** RA-01, RA-08 · **Rejection Count:** 0

#### Problem / Goal
`pub publish --dry-run` возвращает exit 65: 10 tracked `*.log` игнорируются `.gitignore`. Корневой `.pubignore` заменяет корневой `.gitignore`, поэтому всё не перечисленное в `.pubignore` публикуется.

#### Architect Decision
- Tracked `*.log` удалены в RA-08; проверить, что `git ls-files` по-прежнему не содержит файлов, игнорируемых `.gitignore`.
- В `.pubignore` добавить: `/doc/archive/`, `/todo*.md`, `/pre-release-todo.md`, `/completed.md`, `/scratch_rt_check/`, `/test/tmp_verify/`, `/test/probe/baseline/`; сохранить существующие строки.
- Allowlist верхнего уровня архива: `CHANGELOG.md`, `LICENSE`, `README.md`, `CMakeLists.txt`, `analysis_options.yaml`, `ffigen.yaml`, `pubspec.yaml`, `android/`, `assets/`, `example/`, `ios/`, `lib/`, `linux/`, `macos/`, `src/`, `test/`, `test_native/`, `tool/` (только `verify_bindings_audit.dart`, `reference/`, `wasm/build_wasm.sh`, `wasm/README.md`, `abi_v1_wasm_harness.cjs`), `windows/`.

#### Definition of Done
- [x] `flutter pub publish --dry-run` — 0 warnings (hint о скачке версии от 0.2.4 допустим)
- [x] Дерево в выводе совпадает с allowlist; в отчёте — итоговый размер архива
- [x] `yuv_ffi.js` и `yuv_ffi.wasm` присутствуют в выводе

#### Validation / Testing
Вывод dry-run приложить к отчёту (дерево верхнего уровня + итоговая строка размера).

#### Executor Report
После добавления `/dart_test.yaml` в `.pubignore` dry-run на чистом коммите `e66751e` завершился с кодом 0: 0 warnings, 1 допустимая hint о скачке версии с 0.2.4; сжатый архив — 974 KB. Верхний уровень точно совпал с allowlist RA-02; `dart_test.yaml`, архивы и `tool/bench/` отсутствуют. В дереве есть `assets/wasm/yuv_ffi.js` и `yuv_ffi.wasm`. Файлы `*.log` и `*.nv12` отсутствуют в `git ls-files`.

#### Review
Проверены полный dry-run log и список верхнего уровня; публикация не выполнялась.

---

### RA-04 — Переименовать тесты с номерами задач
**Status:** DONE · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** RA-01, RA-05, RA-06 · **Rejection Count:** 0

#### Architect Decision
`git mv`:
- `test/bgra03_dest_alloc_test.dart` → `test/convert_destination_allocation_test.dart`
- `test/bgra04_copy_out_test.dart` → `test/convert_copy_out_test.dart`
- `test/opt14_copy_contract_test.dart` → `test/plane_row_copy_contract_test.dart`
- `test/rel05_independent_results_test.dart` → `test/independent_results_test.dart`
- `test/web/rel05_independent_results_web_test.dart` → `test/web/independent_results_web_test.dart`
- `test/rel06_deprecated_api_test.dart` → `test/deprecated_api_test.dart`
- `test/rel06_public_surface_test.dart` → `test/public_surface_test.dart`
- `test/rel20_encode_decode_test.dart` → `test/encode_decode_test.dart`
- `example/integration_test/rel02_rel05_web_regression_test.dart` → `example/integration_test/web_ownership_regression_test.dart`
- `example/integration_test/yuv40_web_matrix_abort_test.dart` → `example/integration_test/web_matrix_abort_test.dart`

Обновить все упоминания путей в `.github/workflows/ci.yml` и README.

#### Constraints / Non-goals
Содержимое тестов не меняется (описания чистит RA-14).

#### Definition of Done
- [x] Все 10 файлов переименованы; старых имён нет ни в CI, ни в README
- [x] `flutter analyze lib test` — чисто; локально 703 теста; в CI run `36415310682` прошли все jobs, кроме WASM rebuild gate RA-40, который останавливает Web job до интеграционных целей.

#### Validation / Testing
`flutter analyze lib test`; `flutter test` — количество тестов не уменьшилось (сравнить со значением до правки).

#### Executor Report
Переименованы 10 тестовых файлов и обновлены пути в CI/README. `flutter analyze lib test` чистый, `flutter test` прошёл 703 теста. В run `36415310682` все jobs прошли, кроме `wasm-web-integration`, где сравнение пересобранных WASM assets остановилось до Web integration целей; причина зарегистрирована в RA-40 и не связана с переименованием.

#### Review
Старые имена не найдены в CI и README; новые файлы существуют. Анализ и число тестов подтверждены локально. CI подтверждает остальные платформенные jobs; Web target names требуют повторной проверки после RA-40.

---





### RA-16 — Комментарии example
**Status:** DONE · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** RA-01, RA-04 · **Rejection Count:** 0

**Scope:** `example/lib/**`, `example/test/**`, `example/integration_test/**` (кроме архивированного), `example/pubspec.yaml` (комментарии), `example/README.md`.
**Architect Decision:** DOC-RULES. `example/README.md` — короткое описание: что показывает пример, как запустить на каждой платформе, какие разрешения камеры нужны.
**Validation:** `cd example && flutter analyze && flutter test`.

#### Executor Report
README описывает запуск для настроенных Android, iOS, macOS, Windows и Web runners, доступ к камере и необходимые разрешения; Web указан как partial WASM backend. Удалены служебные номера задач из комментариев example README, pubspec, benchmark/camera helpers и Web integration tests.

`cd example && flutter analyze` — чисто; `flutter test` — 71 тест прошёл. Dart format сообщил 0 изменённых файлов. Проверка DOC-RULES оставляет только runtime строки для CI (`YUV-12`, `YUV-40`, `YUV-06`) и технические имена до перехода состояния (`pre-screen`, `pre-injection`); не переписывал их как текст сообщений или терминов.

#### Review
Проверено: изменения ограничены текстом документации, комментариями и описаниями тестов; логика приложения не менялась. Analyze, 71 тест и форматирование выполнены после правки.

---


### RA-19 — Служебные README и комментарии CI
**Status:** TODO · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** RA-22, RA-23, RA-41 · **Rejection Count:** 0

**Scope:** `tool/wasm/README.md`, `assets/wasm/README.md`, `test_native/README.md`, комментарии `.github/workflows/ci.yml`.
**Architect Decision:** DOC-RULES; в `ci.yml` менять только строки `#`.
**Validation:** `actionlint` при наличии, иначе YAML-парсинг (`python -c "import yaml,sys;yaml.safe_load(open(sys.argv[1]))" .github/workflows/ci.yml`).

---

### RA-21 — Пробы: корректность (golden-хэши)
**Status:** REVIEW_AT_END · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** RA-06, RA-08, RA-13 · **Rejection Count:** 0

#### Problem / Goal
Полный поведенческий набор запускается только на Linux x64 VM (CI) и Windows локально. На Android/iOS/macOS/Linux-app проверяется только smoke 4×4 («не нули»). 44 из 119 референсных случаев сравниваются с допуском, поэтому дрейф переписанных ядер может пройти незамеченным.

#### Architect Decision
- Матрица: форматы I420/NV12/BGRA8888 × размеры 1×1, 2×2, 3×5, 16×9, 33×17, 127×255 × раскладки `tight`, `padded` (+7 байт к rowStride), `gap` (I420 pixelStride 2 для Y и UV, NV12 UV pixelStride 3, BGRA pixelStride 5) × 22 операции: grayscale, blackWhite, negate, gaussian(r3, σ2), box(r2), mean(r2), box c ROI, mean c ROI, crop со смещением 1, crop по чётной границе, cropped, flipH, flipV, rotation 90/180/270, toI420, toNv12, toBgra, toBgraBytes, applyRgbaBytes, chromaSwap (только NV12) — всего 1188 случаев. Вход детерминирован LCG. Исходник матрицы — архитектурный харнесс [`doc/archive/audit-2026-09-27/regress_dump_seed.dart`](doc/archive/audit-2026-09-27/regress_dump_seed.dart): форматы, размеры, раскладки, операции, LCG (`_seed = 12345 + width * 31 + height`, пересчёт перед каждым случаем) и формат id `<format> <W>x<H> <layout> <op>` переносить из него без изменений. Оракул 0.4.0 — [`regress_dump_v040.txt`](doc/archive/audit-2026-09-27/regress_dump_v040.txt), 1188 строк.
- **Layout после PACK-01B:** фабрики по умолчанию упаковывают переданные плоскости. Случаи `padded` и `gap` создают образ с `layout: YuvPlaneLayout.preserve`, иначе они молча превратятся в `tight`. Отдельная группа случаев проверяет умолчание `.packed` и `pack()`: для каждой раскладки хэш `toBgraBytes()` до и после упаковки совпадает, `isTightlyPacked` после `pack()` — `true`.
- Результат случая — строка ровно в формате харнесса: для `YuvImage` — `<format> <W>x<H> <sha16(toBytes)> src=<sha16(toBytes источника)>`, для `Uint8List` — `<sha16>`, для ошибки — `ERR <runtimeType>`. Строка оракула — это id до `: ` и значение после. В `golden.json` значения матрицы хранятся в том же виде, поэтому сравнение с оракулом — простое равенство строк.
- **Раскладка файлов (одна операция — один файл, без центрального реестра логики):**
  - `test/probe/cases/<operation>.dart` — только данные случаев операции;
  - `test/probe/cases.dart` — список файлов операций, одна строка на операцию;
  - `test/probe/golden.json` — `{"schema":1,"cases":{"<id>":"<hash>"}}`;
  - `test/probe/probe_correctness_test.dart` с `@Tags(['probe'])` — не пропускается при отсутствии native, а падает;
  - `test/probe/operation_coverage_test.dart` — у каждого значения `YuvOperation.values` есть файл случаев; новая операция без случаев = красный тест.
- **Golden только дополняется.** Режим записи `PROBE_RECORD=1` дописывает отсутствующие id; перезапись существующего id — только с `PROBE_RECORD=overwrite` и отметкой в отчёте как изменение поведения. Новый случай без эталона — тест падает с сообщением «нет эталона».
- Golden записывается на Windows x64 от HEAD. Эквивалентность с 0.4.0 доказывается сравнением с оракулом `regress_dump_v040.txt`: для каждого из 1188 случаев матрицы хэш в `golden.json` равен хэшу оракула (0 расхождений). Сборка 0.4.0 не нужна. Случаи группы `pack()`/`layout` в оракуле отсутствуют и в сравнение не входят. Сравнение везде точное.
- Архитектор проверил 28.09.2026: харнесс на HEAD `fda3215` (native собран MSVC Release) с `layout: YuvPlaneLayout.preserve` даёт дамп, побайтно равный оракулу (SHA-256 файла `69BE886405F75E50…`, 0 расхождений из 1188, 0 ошибок). Если у исполнителя расхождение — это дефект порта харнесса, а не повод обновить golden.
- `dart_test.yaml` в корне: теги `probe` и `release`; `release` исключён по умолчанию.
- Example: `example/integration_test/probe_native_test.dart` (все native-платформы) и `probe_web_test.dart` (WASM) + копии `test/probe/**` в `example/integration_test/helpers/probe/` и `golden.json` в `example/assets/probe/`; копирование — расширить `example/tool/copy_reference_fixtures.sh`; `test/probe/probe_copy_sync_test.dart` проверяет побайтное совпадение копий.
- Расхождение golden на какой-либо платформе не ослабляется допуском: исполнитель RA-22/23/25/41 переводит карточку в ARCHITECT_REQUIRED с перечнем случаев.

#### Constraints / Non-goals
Не менять `lib/`, `src/`. Не заменять существующий референс 119 случаев. Замер скорости — RA-26, здесь только корректность.

#### Definition of Done
- [ ] ≥ 1188 случаев матрицы + группа `pack()`/`layout`; в golden ≥ 900 различных хэшей (чувствительность)
- [ ] Доказано 0 расхождений с 0.4.0 на общих случаях (лог в отчёт)
- [ ] `operation_coverage_test` зелёный; удаление любого файла случаев делает его красным (негативный контроль в отчёте)
- [ ] Негативный контроль: изменение одного хэша в golden валит тест
- [ ] VM-тест и example-цель проходят на Windows локально (`flutter drive -d windows`)

#### Validation / Testing
`flutter test --tags probe`; `flutter test test/probe/probe_copy_sync_test.dart`; `cd example && flutter drive --driver=test_driver/integration_test.dart --target=integration_test/probe_native_test.dart -d windows`.

#### Executor Report
Восстановленный seed harness выдал 1188/1188 строк, идентичных сохранённому 0.4.0 oracle. Созданы 22 отдельных файла с данными операций, golden с 1188 случаями и 949 уникальными результатами, проверка покрытия 12 значений `YuvOperation`, синхронизация копий и layout/pack suite на 54 сочетаниях. `flutter test --tags probe`, copy-sync/coverage/layout suite, analyze и Windows `flutter drive` прошли; Windows log подтвердил 1188 случаев. Web target добавлен; локальный запуск требует ChromeDriver на порту 4444, браузерный gate остаётся RA-41.

#### Review
Ожидает финального независимого ревью.

---

### RA-26 — Пробы: замер скорости
**Status:** IN_PROGRESS · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** RA-21 · **Rejection Count:** 0

#### Problem / Goal
Агент должен одной командой узнать по каждой операции: корректна ли она, стала ли быстрее или медленнее. Регрессия 0.4 (ядра в 10–350 раз медленнее 0.2.4) была замечена только по жалобе.

#### Architect Decision
- Файлы операций RA-21 (`test/probe/cases/<operation>.dart`) дополняются необязательными сценариями замера. Общий исполнитель `test/probe/probe_runner.dart` — только цикл: прогрев, N замеров, медиана и разброс, сравнение с базой. Логики операций в нём нет.
- Вход — общий детерминированный кадр: `test_pattern_512.png`, растянутый ближайшим соседом до нужного размера в коде (без новых больших ассетов), либо LCG для раскладок. Одно определение входа для VM и устройства.
- Размеры для замера: 1920×1080 и 720×360. Замеряется полный публичный вызов.
- Вердикт в строке `PROBE <op> <scenario> <size> PASS|FAIL <median> ms (baseline <x>, ±<p>%) FASTER|SAME|SLOWER|NO-BASELINE` и в `probe-result.json`.
  - `SLOWER`, если медиана хуже базы больше чем на max(15%, 2 × разброс);
  - `FASTER` — симметрично;
  - несовпадение хэша — всегда FAIL (красный тест);
  - `SLOWER` краснеет только при `PROBE_STRICT=1`; в CI скорость только пишется в отчёт.
- База: `test/probe/baseline/<host-id>.json`, где `<host-id>` = ОС, модель CPU/устройства, ABI, режим сборки. Обновление только через `PROBE_RECORD=1`.
- Контроль окружения (иначе замер помечается `INVALID-ENV`):
  - Windows — питание от сети, схема питания Balanced (GUID `381b4222-f694-41f0-9685-ff5bb260df2e`). Не менять схему питания; записывать фактическое имя/GUID в окружение каждого результата;
  - Pixel 3 — `mWakefulness=Awake`, экран включён, keyguard снят, нет thermal throttling (`dumpsys thermalservice`), пауза остывания между операциями.
- Команды:
  - Windows: `flutter test --tags probe` в Release-сборке native; Dart в JIT честно помечается в отчёте.
  - Pixel 3: `tool/probe/run_android.ps1 [-Ops convert,crop] [-Abi arm64|armv7]` — `flutter drive --profile` цели `integration_test/probe_native_test.dart`.

#### Current Environment Correction — Engineer, 28.09.2026
Balanced is the intended Windows measurement contour. The machine currently reports the Balanced scheme GUID above and AC power; no power setting change is allowed or needed. Current RA-26 runners accept Balanced + AC, and no current RA-26 result is classified `INVALID-ENV` because of Balanced. One pre-correction JIT attempt was rejected by the old High Performance-only gate in `tool/probe/run_windows.ps1`; that diagnostic was not accepted as a baseline and has been superseded. Historical MEAS-01/03 archives describe their earlier High/Ultimate protocol and do not define the RA-26 environment policy.

#### Architect Decision 28.09.2026 — Windows Release benchmark
`flutter test` has no Release mode, so JIT timings are diagnostic only. Add `example/probe/windows_release_benchmark.dart` outside frozen `example/lib/`; it must require `kReleaseMode`, initialize `YuvFfi`, execute `probeScenarios` + `runProbe` for all 12 operations × 2 sizes, validate the 24 unique IDs/hashes and sample hash stability, and atomically write one JSON verdict to a unique host-provided result path. Host rejects timeout, missing/stale/malformed/duplicate verdict, wrong run ID, `INVALID-ENV`, nonzero exit, incomplete matrix, or hash mismatch. Retain and hash each timed invocation result after the stopwatch stops so AOT cannot elide the operation.

For 0.4.0 ↔ HEAD, build identical benchmark source in separate detached worktrees with Flutter 3.44.9: a detached `0.4.0` package worktree; a committed HEAD baseline app worktree whose temporary `example/pubspec_overrides.yaml` points `yuv_ffi` to the tag; and a HEAD app worktree with its normal dependency. Verify package_config resolution, package revision, EXE/DLL SHA-256, and common CPU/power contour. Tight benchmark scenarios must be compatible with 0.4.0: omit only `YuvPlaneLayout.preserve` on already-tight inputs and move the deterministic seed helper out of modern `probe_support.dart`. Do not change public API/native C. Persist accepted tag baseline at `test/probe/baseline/windows-<cpu>-x64-release.json`; keep raw runs and comparison report in `doc/archive/release-0.4.2/ra26-windows-release/`.

#### Execution Report — Windows diagnostic JIT, 28.09.2026
The canonical Balanced GUID is active; read-only `root\\wmi:BatteryStatus` returned `PowerOnline=True`, `Discharging=False`. Added a 10-minute test timeout because the full 24-case JIT matrix exceeded test's default 30 seconds. Two full unrecorded runs passed all 24 cases and hashes matched 24/24, but per-case median deltas ranged −47.6% to +23.4%; these runs are unstable diagnostics, not Release baseline evidence. Negative controls passed: injected delay produces strict `SLOWER`/FAIL; wrong golden produces `HASH-MISMATCH`/FAIL. No baseline file was written.

#### Execution Report — Windows Release runner, 28.09.2026
Added `example/probe/windows_release_benchmark.dart` and `tool/probe/run_windows_release.ps1`, plus a pure `test/probe/probe_seed.dart` so the shared tight-input scenarios can compile against 0.4.0. The Release app explicitly checks `kReleaseMode`, emits one atomic JSON verdict, and verifies sample hashes after timing; the host checks a clean exact SHA, Balanced/AC, run ID, full 24-scenario matrix and result integrity. Scoped runner tests passed 10/10, analysis and PowerShell parse passed. Dirty-worktree smoke (`-AllowDirtySmoke`) built/launched Windows Release and returned 24 PASS scenarios with nine sample hashes each; `sourceVerified=false`, saved only in `%TEMP%`, so it is not comparison evidence. Next: commit implementation, build same benchmark source against tag 0.4.0 and committed HEAD in separate worktrees, collect stable repeats and archive raw reports.

#### Execution Report — Pixel 3 arm64 profile diagnostic, 28.09.2026
Corrected Pixel preflight passed: awake, display on, keyguard unlocked, thermal status 0. `flutter drive --profile` completed with exit 0 and `All tests passed`; the strict host accepted exactly one `RA26_ANDROID_RESULT` and emitted `RA26_ANDROID_HOST_RESULT PASS`. Run ID `095d9d326eee4afca9fa1aba1f1a8b68`, device `8B1X11QLW`, ABI `arm64-v8a`, SHA `d8d8d481948f483ef7aa53ed939fbf1db0b962c9`, run-set SHA-256 `2f036abd3bd82f76bff576af34351eefade43ede1686769e2e851c99d6557a46`; 24/24 scenarios PASS with nine samples per scenario. This was a dirty-worktree diagnostic (`sourceVerified=false`), so it created no baseline or archived comparison evidence. Release verification remains separate under RA-25.

#### Integration check — 28.09.2026
The shared root/example `layout_pack_test.dart` files were missing the new `probe_seed.dart` import; Terra fixed both imports. `dart format`, staged/unstaged `git diff --check`, scoped probe/reference tests (122 passed), and the full root suite (711 passed, 1 intentional skip) passed. The existing workspace `yuv_ffi.dll` was supplied through the process-local `PATH` (SHA-256 `9c816b9f59ee159573575c2916321693ae035161d99b92274d9fc21a22365f30`); this is not a fresh native build. CMake is absent on this Windows runner, so a CI-style native build cannot be reproduced locally. `tool/bench/` remains untracked and outside the index. RA-14 was accepted after one comment-only correction; candidate commit is now unblocked.

#### Baseline package provenance audit — 28.09.2026
The initial audit found that the runner proved app Git SHA but not the dependency package selected from `example/.dart_tool/package_config.json`; default `pubspec.yaml` points to HEAD. The required baseline app worktree on committed HEAD must resolve `yuv_ffi` to detached tag `0.4.0` through a controlled `pubspec_overrides.yaml`. That gap is addressed by the implementation report below; no comparison is accepted until validation-only positive/negative proof passes in the clean baseline app worktree.

#### Baseline package provenance gate — implementation report, 28.09.2026
The runner now supports an explicit baseline mode that accepts only the expected temporary override, runs `flutter pub get`, resolves `yuv_ffi` from `example/.dart_tool/package_config.json`, checks the resolved clean tag worktree and package revision, and records app SHA and package path/revision separately in the host verdict. A contract test covers accepted tag resolution, wrong path/revision rejection, and required provenance fields; focused tests passed 10/10 and PowerShell parsing passed. Since `pub get` changes the baseline app's `example/pubspec.lock` plus three tracked Windows generated files, the runner restores exactly this known set in `finally`. Next: commit/push this fix, then run validation-only positive/negative proof in a clean baseline app worktree. No benchmark timing is accepted until provenance passes.

#### RA-25 evidence archive — 28.09.2026
Both Pixel 3 Release gates passed and host evidence is prepared under `doc/archive/release-0.4.2/ra25-pixel3/`: README, arm64/armv7 stdout and stderr, and the final arm64 logcat record. APK SHA-256 values: arm64 `6a175d1dd106bf952489d168f6b9c526ffa260f353b1c02359dec54b2911980f`; armv7 `6543c93155847ba951168a3a4adeb5dd34713335d4fe2719244b137150b4e243`. Both reports prove target-only ABI and `libyuv_ffi.so` ZIP contents, installed `primaryCpuAbi`, unique strict `RA25_RESULT`, smoke/probe PASS, and 1188 cases. Reports are uncommitted pending the next status commit; independent T1 acceptance remains.

#### Definition of Done
- [ ] Сценарии замера для всех 12 `YuvOperation`
- [ ] Базовые линии Windows x64 и Pixel 3 arm64 сняты для тега 0.4.0 и для HEAD; таблица сравнения — в отчёте (источник цифр для CHANGELOG RA-18)
- [ ] Негативный контроль: искусственное замедление (sleep в тестовой сборке исполнителя, не в `lib/`) даёт `SLOWER`, испорченный golden даёт FAIL
- [ ] Два повторных прогона на одной машине дают `SAME`

---

### RA-27 — Правило проб в AGENTS.md
**Status:** TODO · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** RA-26 · **Rejection Count:** 0

#### Architect Decision
Добавить в `AGENTS.md` проекта раздел «Probes»:
- В карточке задачи поле `Probe: none | windows | windows+pixel3`. Правка `src/` или `lib/src/yuv/impl/**`, а также любая заявка о скорости → `windows+pixel3`; прочие правки `lib/` → `windows`; документация и CI → `none`.
- Исполнитель прогоняет пробу на Windows и прикладывает строки вердикта к отчёту. FAIL — задача не сдаётся. `SLOWER` — объяснить или исправить.
- Ревьюер прогоняет пробу на Pixel 3 (arm64; при правке `src/` — ещё и armv7). Задача принимается, только если обе пробы PASS и нет необъяснённого `SLOWER`.
- Базу обновляет не исполнитель, а ревьюер после приёмки, отдельным коммитом с причиной.
- Остальные платформы: корректность проверяется в CI на каждом push, скорость — на предрелизной проверке.

#### Definition of Done
- [ ] Раздел добавлен
- [ ] Шаблон карточки (в `todo.md`) содержит поле `Probe`

---

### RA-22 — Проба корректности в платформенных CI-джобах
**Status:** READY_FOR_CI · **Tier:** T2 · **Execution Mode:** FAST · **Review Tier:** T1 · **Depends On:** RA-04, RA-06, RA-21 · **Rejection Count:** 0

**Architect Decision:** в `linux-native-smoke`, `macos-native-smoke`, `ios-native-build`, `android-native-build` после шага app-runtime smoke добавить шаг, который перебирает `integration_test/*_native_test.dart` (сейчас это `probe_native_test.dart`) на том же устройстве; новая цель с таким суффиксом попадает во все джобы без правки YAML (джоба `android-armv7-runtime` удалена в RA-06; ARMv7 доказывается RA-25). Вердикт выносит общий `tool/ci/drive.sh <target> <device>`: PASS только при exit 0 **и** строке `All tests passed` в выводе; скрипт используют все джобы с `flutter drive`, включая app-runtime smoke.
**DoD:** зелёный CI-run на ветке; в логах каждой из 4 джоб видно выполнение 1188 случаев.
**Validation:** ссылка на run; негативный контроль — один прогон с испорченным golden в отдельном коммите, который красит джобы, затем откатывается.

#### Local Negative Controls — 28.09.2026
Using a temporary fake `flutter` executable without touching the workflow: exit 0 without the terminal marker was rejected (helper exit 1); exit 7 while printing the marker was also rejected (helper preserved exit 7). The required remote corrupted-golden run across the four native jobs remains pending.

---

### RA-23 — Windows CI
**Status:** READY_FOR_CI · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** RA-06, RA-21, RA-22 · **Rejection Count:** 0

**Architect Decision:** новая джоба `windows-native-smoke` на `windows-latest`, Flutter 3.44.9: `cmake -S src -B $RUNNER_TEMP/nb -A x64` + Release; каталог сборки добавить в `PATH`; `flutter test` (полный набор, без пропусков native); `cd example && flutter build windows --release`; `flutter drive -d windows` для `native_app_runtime_smoke_test.dart` и всех `*_native_test.dart` через `tool/ci/drive.sh`. Блокирующая.
**DoD:** зелёный run; в логе `flutter test` нет пропущенных native-тестов.

---

### RA-25 — Физический Pixel 3: arm64 и armv7
**Status:** WAITING_FOR_COMMIT · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** RA-13, RA-21, RA-26 · **Rejection Count:** 0

**Architect Decision:** Flutter Driver не поддерживает `--release`, а `integration_test` release APK не запускает. Заменить невозможный driver gate на отдельный обычный Flutter release entrypoint за пределами `example/lib/` (не менять замороженный продуктовый слой). Он должен выполнить runtime smoke и все 1188 golden probe cases на Pixel 3 arm64 и armv7 через явные проверки `if`/`StateError`, без `assert`, `flutter_test` и `integration_test`. Собрать отдельные APK `flutter build apk --release --target=<entrypoint> --target-platform android-arm64|android-arm --split-per-abi`; проверить SHA и состав каждого APK, установить точный ABI, запустить через ADB и подтвердить `primaryCpuAbi`/загрузку `libyuv_ffi.so`. Результат запускается в logcat одной строгой JSON-записью с SHA, уникальным run ID, ABI, smoke/probe PASS и числом 1188; хост принимает ровно одну запись с ожидаемыми полями, а пропуск, timeout, duplicate, malformed или FAIL — ошибка. Экран должен быть включён, keyguard снят, устройство awake и без thermal throttling. Замеры скорости RA-26 остаются отдельной profile-проверкой.
**DoD:** оба ABI проходят release smoke и 1188-case probe; для каждого ABI закоммичен полный отчёт с SHA, APK hash/content, моделью/Android/ABI, состоянием устройства и logcat verdict.
**Constraints:** это единственный gate для ARMv7 и arm64 Android (CI-джоба armv7 удалена в RA-06).

#### Executor Report
Pixel 3 (`8B1X11QLW`, Android 12, `arm64-v8a,armeabi-v7a,armeabi`) подключён через ADB; экран включён, keyguard снят, thermal status 0. Profile app-runtime smoke и native probe завершились `All tests passed`; probe обработал 1188 случаев. Release APK arm64 и armv7 собраны, в каждой APK подтверждена только целевая ABI и `libyuv_ffi.so`; arm64 APK установлена и запущена без ошибок загрузки библиотеки.

Требуемый `flutter drive --release` прекращается до сборки сообщением, что Flutter Driver не поддерживает release mode. Profile-прогон не подтверждает release assertions, а запуск основного example app подтверждает только открытие приложения. Это историческая блокировка, разрешённая решением ниже от 28.09.2026. Полные команды прежних попыток: `doc/archive/release-0.4.2/pixel3-evidence.md`.

#### Architect Decision 28.09.2026 — standalone release verification
Заменить невозможный Flutter Driver release gate отдельным обычным Flutter entrypoint вне `example/lib/`, без `flutter_test`, `integration_test` и Dart `assert`. Entry point должен выполнить runtime smoke и все 1188 golden probe cases с явными `if`/`StateError`. Собирать release APK по отдельности для arm64 и armv7, проверять SHA-256 и ZIP-состав целевого ABI/`libyuv_ffi.so`, установить именно этот ABI, подтвердить `primaryCpuAbi` и единственную строгую JSON-запись `RA25_RESULT` из logcat с ожидаемым SHA, run ID, ABI, smoke/probe PASS и `caseCount: 1188`. Пропуск, timeout, duplicate, malformed или FAIL — ошибка. Release checks отдельно от profile-замеров RA-26.

**Implementation result:** `tool/probe/release_probe_core.dart`, `example/probe/release_probe.dart`, `tool/probe/run_release_android.ps1` и focused test добавлены. Core и 1188 golden cases прошли, оба split-ABI release APK собраны, analyzer и PowerShell parse прошли; source guard подтвердил отсутствие запрещённых test imports/assert. Реальный APK hash/ADB/logcat/`primaryCpuAbi` gate ещё не запускался; он ожидает согласованный финальный commit SHA.

---

### RA-40 — Пересборка WASM
**Status:** READY_FOR_CI · **Tier:** T2 · **Execution Mode:** FAST · **Review Tier:** T1 · **Depends On:** RA-06, RA-08, RA-13 · **Rejection Count:** 0

#### Problem / Goal
`assets/wasm/*` собраны в `d447fb2`, до 14 C-коммитов; доказано, что исходники HEAD дают другой `.wasm`. CI-гейт сравнивает с пересборкой на emsdk 3.1.74 и упадёт.

#### Architect Decision
На Windows runner `dev.working` использовать изолированный emsdk 3.1.74 из `D:\.projects\.tools\emsdk-3.1.74`; локальный emsdk 5.0.1 не использовать. Пересобрать assets из checkout, подтвердить повторяемость и включить их в commit. CI job сравнивает committed assets с чистой повторной сборкой на том же runner. GitHub-hosted `upload-artifact` не требуется: по решению Engineer только единый Linux smoke/sanitizer job остаётся hosted, а Web/WASM проверяется на Windows self-hosted.
**DoD:** следующий run: шаг сравнения зелёный; `git log -1 -- assets/wasm` новее последнего коммита в `src/`.

#### Local Reproducibility Report — 28.09.2026
Two isolated `emsdk 3.1.74` release builds in ignored `tool/wasm/out/ra40-a` and `ra40-b` matched the committed assets and each other. SHA-256: `yuv_ffi.js` = `DC5E08EE24EC15D1F10F829D2EB71EA0BFC944F50F63CC14E010EC6C853F39D5`; `yuv_ffi.wasm` = `BAD2FC75799FE29FB40FD9866C2D106B3FA13F1929C41F7A219301C8C0F1D08F`. No tracked files changed. Remaining blocker: CI comparison on the release candidate SHA.

---

### RA-41 — Зелёный Web-гейт
**Status:** READY_FOR_CI · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** RA-04, RA-21, RA-22, RA-40 · **Rejection Count:** 0

**Architect Decision:** заменить явный список целей `Required Web integration gate` перебором `integration_test/*_web_test.dart` (включая `probe_web_test.dart`; существующие web-цели из списка переименовать в этот суффикс в этой же карточке); обновить имена целей после RA-04. В цикле и в шаге матрицы 119 вердикт PASS — только при exit 0 **и** строке `All tests passed` в выводе через `tool/ci/drive.sh` из RA-22. Если golden расходится на WASM — ARCHITECT_REQUIRED со списком случаев (не ослаблять).

#### Architect Decision 28.09.2026 — Windows browser test runner
Flutter 3.44.9 on Windows maps `path.fromUri()` to backslashes while its web test selector uses slash paths. The fake-module `flutter test --platform chrome` suites therefore hang at `+0` before registration. Move the three suites intact into `example/integration_test/*_web_test.dart`, use the integration test binding and `testWidgets`, and run them through ChromeDriver + `tool/ci/drive.sh`; remove the standalone browser unit-test CI step and keep the dynamic target glob as the authoritative gate.

**Local implementation result:** 39 static registrations preserve 41 runtime cases. All three migrated targets passed with exit 0 and `All tests passed` (48.1 s, 48.4 s, 45.8 s); `flutter analyze integration_test` passed with 12 existing legacy deprecation infos. The full dynamic gate passed 13/13 locally. Separate `reference_web_conversions_test.dart` passed 119/119 with zero mismatches in 645.1 s; committed WASM asset hashes were unchanged before/after. Remaining: integrated CI green on one candidate SHA and a remote negative control proving the gate fails on deliberately corrupted WASM, followed by revert.
**DoD:** зелёная джоба `wasm-web-integration`; негативный контроль (обнуление первых 64 байт `yuv_ffi.wasm` во временном коммите) красит гейт, затем откат.

**Локальный Windows Web-run:** ChromeDriver находится в `D:\.projects\.tools\chromedriver-win64\chromedriver.exe` (154.0.8037.57), установленный Chrome — 154.0.8037.58. Запустить `chromedriver --port=4444`, затем из `example/`: `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/probe_web_test.dart -d web-server --browser-name=chrome --headless`. Эта запись хранится в `pre-release-todo.md`, исключённом из pub archive правилом `/pre-release-todo.md` в `.pubignore`.

**Исторический результат до исправления seed:** driver/browser подключились; после пересборки assets через emsdk 3.1.74 матрица дала как минимум 20 несовпадений. Т1 установил, что Web генерировал другие входные байты из-за неточной LCG-арифметики dart2js; golden и оракул верны. Этот результат и блокировка из `doc/archive/release-0.4.2/web-probe-evidence.md` сняты исправлением seed, описанным ниже. После исправления ChromeDriver probe прошёл 1188 операций без mismatches; полный dynamic gate 13/13 целей и отдельная 119-case reference matrix (119/119, mismatches 0) также локально зелёные. Ожидаются CI на общем candidate SHA и remote negative control.

#### Architect Decision 28.09.2026 — причина расхождений на Web

**Дефект в генераторе входа пробы, а не в WASM и не в C.** Golden и оракул 0.4.0 остаются верными.

Генератор байтов в `test/probe/probe_support.dart:140` и `test/probe/layout_pack_test.dart:29` — `seed = (seed * 1103515245 + 12345) & 0x7fffffff`. На VM это точная 64-битная арифметика. В dart2js `int` — это IEEE double: `seed * 1103515245` доходит до ~2,4·10¹⁸ > 2⁵³ и теряет младшие биты, а `&` в JS работает с 32-битным усечением. На Web тест получает **другие входные кадры**, поэтому расходятся все случаи, а не только gray: gray просто идёт первым файлом `cases.dart`, и отчёт показывает первые 20.

Проверено архитектором: одна и та же функция скомпилирована в VM и в dart2js (запуск в Node). Последовательность расходится со второго шага (`firstDiff=1`, контрольная сумма 200 000 байт `830980134` на VM и `86505086` в dart2js). Точная web-безопасная замена ниже даёт в dart2js ту же сумму `830980134`, что и VM, то есть совпадает побайтно.

**Что сделать:**
1. В обоих местах заменить шаг генератора на точный эквивалент, у которого все промежуточные значения меньше 2⁵³ и нет побитовых операций над большими числами:
   ```dart
   /// Same sequence as `(s * 1103515245 + 12345) & 0x7fffffff`, computed
   /// exactly on the web too: every intermediate stays below 2^53.
   int probeNextSeed(int s) {
     const aHi = 16838; // 1103515245 ~/ 65536
     const aLo = 20077; // 1103515245 % 65536
     final hi = (s * aHi) % 32768;
     return (s * aLo + hi * 65536 + 12345) % 2147483648;
   }
   ```
   Функция объявляется один раз в `probe_support.dart`; `layout_pack_test.dart` использует её, а не свою копию. `(seed >> 8) & 0xff` менять не нужно: `seed < 2³¹`.
2. Синхронизировать копии в `example/integration_test/helpers/probe/` штатным скриптом копирования.
3. Отчёт о расхождениях: в `expectProbeMismatchesEmpty` выводить общее число расхождений и первые 20, а не только первые 20.
4. Добавить быструю проверку входа, чтобы отличать «другой вход» от «другой результат»: в `golden.json` дописать (режим `PROBE_RECORD=1`, записать на VM) id `input <format> <W>x<H> <layout>` со значением sha16 от `toBytes()` сгенерированного исходного кадра до операции; `probe_correctness_test` и `probe_web_test` проверяют эти id первыми и падают с сообщением «генератор входа расходится на этой платформе».

**Проверка:**
- VM: `flutter test --tags probe` — 0 расхождений с существующим golden (последовательность не меняется, эквивалентность доказана выше) и совпадение с оракулом 0.4.0.
- Web (локально, как в записи выше): 0 расхождений. Если после исправления остаются расхождения — вход уже гарантированно одинаковый, значит это реальное различие WASM и native. Тогда ARCHITECT_REQUIRED с **полным** списком, golden не менять.
- Затем прежний DoD: зелёная CI-джоба и негативный контроль.

---

### RA-18 — Финальный CHANGELOG 0.4.2
**Status:** TODO · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** все RA кроме RA-50 · **Rejection Count:** 0

**Architect Decision:** убрать «draft; not published» и фразу о незавершённом рефакторинге. Разделы: Highlights; Performance (ускорение native-ядер и Dart-копирования; цифры — только измеренные, с платформой и размером; поведение побайтно совпадает с 0.4.0 по набору соответствия); Behavior change первым пунктом (умолчание `YuvPlaneLayout.packed`, решение D-1: версия остаётся 0.4.2); New API (`YuvFramePresenter`, `YuvFrameView`, `YuvPlaneLayout`, `isTightlyPacked`, `pack()`); Changes (`YuvImageProvider`: копия при старте декодирования, `StateError` для мутированного провайдера; пересобранный WASM); Documentation fixes (ROI и crop — пиксельные координаты; `copy(blank: true)` сохраняет strides; `initialize()` обязателен на IO для `apply*`); Example; Known limitations; Moving from a 0.4.0 lockfile. Без номеров задач. Держать версию в синхронизации с `pubspec.yaml`.

---

### RA-50 — Финальный релизный гейт
**Status:** TODO · **Tier:** T2 · **Execution Mode:** FAST · **Review Tier:** T1 + Engineer · **Depends On:** все RA · **Rejection Count:** 0

**DoD:**
- [ ] Один финальный SHA; на нём зелёные **все** CI-джобы (non-blocking джоб в workflow нет)
- [ ] `flutter pub publish --dry-run` — 0 warnings; дерево по allowlist RA-02
- [ ] Версия 0.4.2 совпадает в `pubspec.yaml`, `CHANGELOG.md`, `ios|macos/*.podspec`, `src/CMakeLists.txt`
- [ ] Плейсхолдеры README заменены ссылками на run финального SHA и на доказательство RA-25
- [ ] Отчёт: список run, известные ограничения, что проверено вручную
**Constraints:** не создавать тег и не публиковать — это Engineer.
