# CI 4 — Skwasm «Picture was disposed» в Web CI на Mac
**Status:** DONE · **Tier:** T2, Reviewer T1 · **Owner:** — · **Depends On:** CI 3 · **Probe:** none

**Base SHA:** 36be42f559af5ff9275efc6c2ef0a1c6e7f5df37 (SHA `dev` после перевода CI 3 в `REVIEW`)

#### Goal

Web CI на Mac (`ci-web.yml`, `yuv-self-hosted`) зелёный целиком. После карточки причина падения
`all_web_test.dart --wasm` с ассертом Skwasm `The native object of Picture was disposed` в run 37336100554 установлена
и подтверждена воспроизведением; ясно, касается ли она пакета (`lib/`) или только тестового окружения; падение
устранено без ослабления проверок. Сюда же перенесены зелёный workflow на Mac и замер `ci/all` из CI 3 (а туда — из
CI 2 по D-32). Карточка идёт до выпуска 0.5.1; `release/0.5.1` (`61da2ee`) она не меняет.

#### Diagnosis

Факты на 05.10.2026; нужны только на старте.

- Run 37336100554 (`8fb5223`, `yuv-self-hosted`, 22m12s): прошли сборка WASM, вся JavaScript-матрица, reference,
  camera smoke и первые две цели `--wasm` (`probe_web_test.dart`, `shader_probe_web_test.dart`). Упала третья —
  `integration_test/all_web_test.dart --wasm`, одна ошибка:
  `The following assertion was thrown running a test (but after the test had completed)`,
  `org-dartlang-sdk:///lib/_engine/engine/native_memory.dart:112:22` (`!isDisposed`), стек только движка:
  `UniqueRef.nativeObject` → `CountedRef.nativeObject` → `SkwasmPicture.handle` → `SkwasmPicture.cullRect`
  (`_skwasm_impl/picture.dart:68`).
- Skwasm — рендерер сборки `--wasm`; сборка JavaScript (CanvasKit) того же `all_web_test.dart` в этом run прошла.
- **Исправлено 05.10.2026 по отчёту R3:** рисует один источник агрегата — `image_cache_key_web_test.dart`
  (`pumpWidget(MaterialApp(home: YuvImageWidget(...)))`, 4 вызова в группе «the image cache follows the real
  revision»). Остальные 8 работают с данными. `YuvImageWidget` (`lib/src/widgets/yuv_image_widget.dart`) — обычный
  `Image` с `YuvImageProvider`, кадр — `ui.decodeImageFromPixels`; `Picture` в `lib/` не создаётся и не
  освобождается (`PictureRecorder`, `toImage`, `Picture` в `lib/` — нет). Ассерт сработал после завершения теста.
- Где та же цель проходила: Windows — Web CI CI 1 (run 37243974376) и `ci/all/0.5.1` (run 37286266838); Mac по SSH —
  `bash tool/ci/web.sh` в CI 2 (DoD 3) и CI 3 (DoD 4). Падение известно только в workflow на Mac, один раз из одного
  запуска, дошедшего до `--wasm` (run 37301435314 до `--wasm` не дошёл).
- Раннер — Intel Mac (`Intel Mac OS X 10_15_7` в user agent), HeadlessChrome 154, Flutter 3.44.9, служба launchd.
  Тот же раннер медленно инициализировал fake-камеру в CI 3 (3,8–24 с против 0,08 с по SSH).
- `tool/ci/drive.sh` при провале печатает вывод с первой строки `FAILED|EXCEPTION|Error`; имя теста, после которого
  сработал ассерт, в лог run не попало. Полный вывод — только локально.
- Время для сравнения в DoD 6: Web в `ci/all/0.5.1` — run 37286266838 (Windows, ~21 мин); Web на Mac в run
  37336100554 — 22m12s до падения.

#### Architect Decision

1. **Сначала воспроизвести и локализовать.** Порядок:
   - R1 — Mac по SSH, чистый клон на SHA `dev`: `all_web_test.dart --wasm` 10 раз (команда в DoD 1) с полным выводом
     `flutter drive` в файл; записать число падений и имя последнего завершённого теста перед ассертом.
   - R2 — если R1 даёт 0/10: один `gh workflow run ci-web.yml --ref dev`. Падение в workflow при 0/10 по SSH
     указывает на контекст службы раннера.
   - R3 — при воспроизведении: прогнать по отдельности источники агрегата с `--wasm` (по одному на запуск, тем же
     `drive.sh`), чтобы найти источник или пару соседних источников, после которых срабатывает ассерт.
   - Если не воспроизводится ни R1, ни R2 — `ENGINEER_REQUIRED`: «разовый сбой движка; варианты — закрыть с записью
     в `doc/perf-findings.md` или наблюдать до следующего падения; рекомендация — закрыть, если DoD 5 и 6 зелёные».
2. **Известная проблема Flutter.** Поискать в `flutter/flutter` issues по `"native object of Picture was disposed"`
   и `skwasm Picture disposed`; ссылку или «не найдено» — в отчёт.
3. **Влияние на пакет — до любого исправления.** Если R3 или стек указывают на код `lib/` (например, `YuvImage`
   presenter, `toImage`, шейдер) — сразу `ENGINEER_REQUIRED`: это затрагивает заявленную в 0.5.1 поддержку `--wasm`
   и решение о выпуске. Код `lib/` в этой карточке не меняется.
4. **Исправление — первый вариант, прошедший Validation.** Отвергнутые — с логами в отчёте.
   - A1 (тест): источник из R3 оставляет незавершённую работу или кадр после конца теста (не дожидается `Future`,
     не завершает кадр) — исправить этот тест, не меняя его проверок.
   - A2 (движок, подтверждён известной issue или минимальным примером без кода пакета) — `ENGINEER_REQUIRED` с
     вариантами: обновить Flutter; изменить состав целей `--wasm` в `web.sh`/`web.ps1` (например, отдельные цели
     вместо агрегата); принять известный сбой с ссылкой на issue. Рекомендацию дать по фактам R1–R3.
   - A3 (окружение раннера) — `ENGINEER_REQUIRED` с вопросом и рекомендацией; службы раннера не трогать.
5. **Проверки не ослабляются.** Источники агрегата не убираются из `--wasm`, не пропускаются, retry не вводится.
6. **Другие падения** — как в CI 3: факт в отчёт; та же причина — здесь, другая — `ENGINEER_REQUIRED` с предложением
   отдельной карточки.
7. **Время `ci/all`** (из CI 2, п. 7, через CI 3). Таблица «workflow → run → длительность», сравнение Web с run
   37286266838; если неприемлемо дольше — `ENGINEER_REQUIRED` с цифрами.

8. **Граница продолжения (решение Architect по `ENGINEER_REQUIRED` от 05.10.2026).** Факты отчёта: R1 по SSH 10/10
   PASS, R2 в workflow воспроизвёл ассерт (второй раз из двух запусков на раннере, 37336100554 и 37359566518), R3 —
   9/9 одиночных источников PASS, но только по SSH, где агрегат тоже проходит. Участие `YuvImageWidget` в вызове —
   не доказательство дефекта пакета: пакет не владеет ни одним `Picture`. Поэтому:
   - Продолжается test-only локализация по A1 **в контексте раннера** (по SSH сбой не воспроизводится, и R3 по SSH
     ничего не различает). `lib/` не меняется.
   - Диагностические прогоны — временными коммитами в `dev`, как в CI 3: разрешено менять состав
     `example/integration_test/all_web_test.dart` и сузить `tool/ci/web.sh` до цели `all_web_test.dart --wasm`, чтобы
     прогон занимал минуты, а не ~20 мин. Каждый временный коммит отменяется отдельным коммитом до Validation;
     DoD 4–6 идут на неизменённых `web.sh` и агрегате. Не больше 6 диагностических run; итог каждого — строка отчёта
     «SHA → run → состав → результат».
   - Порядок экспериментов:
     - L1 — агрегат без `image_cache_key_web_test.dart`. Падает → `YuvImageWidget` не нужен для сбоя: пакет не
       затронут, переход к A1/A2 ниже.
     - L2 — только если L1 прошёл: агрегат, где `image_cache_key_web_test.dart` заменён временным контрольным
       тестом с тем же сценарием (`pumpWidget`, `pumpAndSettle`, смена `boxFit`) на стандартном
       `Image.memory`/`RawImage` с теми же байтами BGRA вместо `YuvImageWidget`. Падает → сбой вызывает любой
       виджет-рендер в агрегате, пакет не затронут. Проходит при падении исходного агрегата → **граница**: дефект
       пакета не исключён — `ENGINEER_REQUIRED` с предложением отдельной карточки `FIX` (влияет на заявленный
       `--wasm` в 0.5.1), без правки `lib/`.
     - Каждый результат, который может быть случайным, подтвердить повтором того же run (входит в лимит 6).
   - Исправление при «пакет не затронут»: сначала A1 — в виджет-тестах `image_cache_key_web_test.dart` в конце
     каждого теста явно снять дерево (`await tester.pumpWidget(const SizedBox.shrink())`) и дождаться кадра
     (`await tester.pumpAndSettle()`), не меняя проверок; критерий — DoD 3 и DoD 5. Не помогло → A2
     (`ENGINEER_REQUIRED`, варианты из п. 4) с данными L1/L2.
   - Лимит исчерпан без ответа — `ENGINEER_REQUIRED` с собранными run.

#### Scope

Тесты из `example/integration_test/`, найденные R3 или L1/L2 (вариант A1); временные диагностические коммиты по
п. 8 (агрегат, `tool/ci/web.sh`), отменённые до Validation. Отчёт и статус — карточка и `todo.md`.

#### Constraints

- `lib/**`, `src/**`, `assets/wasm/**`, `tool/wasm/**` не менять.
- `tool/ci/**` и `.github/**` не менять без решения Engineer по A2/A3; исключение — временное сужение `web.sh` по
  п. 8, отменённое до Validation.
- Не отключать, не пропускать и не повторять тесты ради зелёного прогона; проверки тестов не менять.
- Службы и метки раннера не трогать. На Mac работать во временном клоне; клон удалить после работы.
- `release/0.5.1` не менять.

#### Definition of Done

1. Воспроизведение записано — check: на Mac в чистом клоне базового SHA при запущенном `~/bin/chromedriver --port=4444`
   10 раз `bash tool/ci/drive.sh integration_test/all_web_test.dart web-server --browser-name=chrome --headless --wasm`;
   в отчёте — «падений N из 10» и фрагмент полного вывода упавшего прогона с именем последнего теста; при 0/10 — run
   R2 с результатом или `ENGINEER_REQUIRED` по п. 1 — by: Executor
2. Причина названа и связана с доказательством — check: отчёт — источник из R3 (или «не локализуется»), ссылка на
   issue Flutter или «не найдено», явная строка «код `lib/` затронут: да/нет» с основанием; выбранный вариант и логи
   отвергнутых — by: Executor
3. После исправления `all_web_test.dart --wasm` стабилен на Mac — check: команда DoD 1, 10 раз на SHA карточки →
   10 из 10 `All tests passed`, exit 0 — by: Executor
4. Локальные проверки по ключам — check: `bash tool/ci/scope_guard.sh <base>` и команды из `AGENTS.md` для каждого
   ключа, доступного на машинах; в том числе Mac `bash tool/ci/web.sh` и Windows `pwsh -File tool/ci/web.ps1` → exit 0 и
   строка `Web CI passed: ...`; по каждому ключу — exit code — by: Executor
5. Workflow на Mac зелёный — check: `gh workflow run ci-web.yml --ref dev`, затем `gh run watch <run-id> --exit-status`
   → exit 0; `gh run view <run-id> --json headSha,jobs --jq '.headSha, .jobs[].runnerName'` → SHA карточки и
   `yuv-self-hosted` — by: Executor
6. `ci/all` на SHA карточки 9/9 и время записано — check: тег `ci/all/CI-4` на SHA карточки; все 9 run `success`,
   `headSha` = SHA карточки; таблица «workflow → run → длительность» и сравнение Web с run 37286266838 — by: Executor
7. Проверки не ослаблены — check: чтение diff тестов против п. 5 Architect Decision — by: Reviewer

#### Validation

Минимум: DoD 1–4 локально (Mac и Windows), 5 — один запуск workflow, 6 — один `ci/all` после остального. Пробы по
`AGENTS.md`: пути карточки — `example/` → `none`. Теги `ci/*` — триггеры; удаляются пачкой в конце цикла. Если
`ci/all` упал вне Web — факт-карточка по `ci.md`, без диагноза.

#### Executor Report

Validated at: a65270a2657ce987a01a4037a76fa474def1d585
1. Предшествующая диагностика: R1 по SSH — 10/10 проходов, R2 [37359566518](https://github.com/Anfet/yuv_ffi/actions/runs/37359566518) воспроизвёл сбой, R3 9/9 одиночных тестов прошли по SSH; как уточнено в п. 8, SSH не воспроизводит контекст ошибки.
2. L1/L2 — временные runner workflows: [L1 #1](https://github.com/Anfet/yuv_ffi/actions/runs/37363432244) и [L1 #2](https://github.com/Anfet/yuv_ffi/actions/runs/37363613775), агрегат без `image_cache_key` — оба PASS; [L2 #1](https://github.com/Anfet/yuv_ffi/actions/runs/37363949585) и [L2 #2](https://github.com/Anfet/yuv_ffi/actions/runs/37364148597), контроль на стандартном `RawImage` — оба воспроизвели тот же Skwasm assert после завершения теста. Это подтверждает ветку п. 8: сбой не требует кода пакета. Четыре временных коммита отменены отдельными revert-коммитами до финальных проверок. Точный текст ошибки искался в issues `flutter/flutter` — не найдено.
3. Выбран A1 — в обоих тестах `image_cache_key_web_test.dart`, которые строят `YuvImageWidget`, добавлены `pumpWidget(const SizedBox.shrink())` и `pumpAndSettle()` после неизменённых assertions.
4. После A1 — Mac `bash tool/ci/drive.sh integration_test/all_web_test.dart web-server --browser-name=chrome --headless --wasm`, 10/10 PASS, exit 0. Полный Mac workflow [37366114659](https://github.com/Anfet/yuv_ffi/actions/runs/37366114659) — success, 22m20s, `headSha=a65270a`, `runner_name=yuv-self-hosted`.
5. `bash tool/ci/scope_guard.sh 441229a` — `scope: all`. Доступные локальные проверки: `vm.ps1` 638/638; `windows.ps1` 134/134, Windows Release build и 5 integration targets; `android.ps1` debug build и 5 integration targets; `example.ps1` pub get/analyze/web build; `smoke.ps1`; Mac `web.sh` (integration=64, reference=119, WASM targets=3); Windows `web.ps1` (то же); `macos.sh` (Release/debug builds, native smoke и 5 integration targets); `ios.sh` (simulator smoke) — все exit 0. После восстановления доступа к Linux VM локально повторён полный native smoke: Debug/Release sanitizer CTest, packaging smoke, Linux Release build, app-runtime smoke и 5 native integration targets — exit 0.
6. Полный Mac workflow [37366114659](https://github.com/Anfet/yuv_ffi/actions/runs/37366114659) — exit 0; `headSha` совпадает с `Validated at`, runner `yuv-self-hosted`.
7. Тег `ci/all/CI-4` на `a65270a`: после повторного запуска CI workflow — 9/9 success; таблица результатов:

| Workflow | Run | Результат | Длительность |
| --- | --- | --- | --- |
| CI VM | 37370821726 | success | 6m36s |
| CI Android | 37370821704 | success | 5m14s |
| Example CI | 37370821733 | success | 8m13s |
| CI | 37370821735 | success, attempt 3; оба job success | 4m08s |
| CI smoke | 37370821856 | success | 6m54s |
| CI Web | 37370821880 | success | 26m36s |
| CI macOS | 37370821912 | success | 4m34s |
| CI Windows | 37370821954 | success | 13m51s |
| iOS CI | 37370821779 | success | 32m06s |

   Web comparison: `ci/all/0.5.1` run 37286266838 — about 21m19s; CI-4 — 26m36s (about 5m17s longer). No performance conclusion is inferred.
8. Diff against base — only two test teardowns were added; all original tests and assertions remain. The L1/L2 aggregator and temporary `web.sh` diagnostic exit path were reverted before these checks.

#### CI rerun — Linux result (per `ci.md`, without diagnosis)

- SHA: `a65270a2657ce987a01a4037a76fa474def1d585`.
- Workflow: `CI`, run [37370821735](https://github.com/Anfet/yuv_ffi/actions/runs/37370821735), trigger tag `ci/all/CI-4`.
- Initial attempt: job `bindings-regeneration` succeeded; `linux-native-smoke` was cancelled. The cancellation had no failed-step excerpt; no diagnosis was performed.
- Rerun attempt 3: both jobs succeeded at the same SHA. `linux-native-smoke` completed all sanitizer, packaging, Linux build, app-runtime smoke and native correctness probe steps in 4m02s. Full workflow concluded success in 4m08s.
- Linux VM local smoke at the same SHA also passed: CTest Debug/Release, packaging smoke, Linux Release build, app-runtime smoke and four native integration targets (`camera_capture`, `presenter_shader`, `probe`, `shader_probe`), exit 0.

DoD 1–6 are complete. DoD 7 remains for Reviewer. The cancelled initial Linux attempt is resolved by the successful rerun; no diagnosis was performed.

#### Review

Verdict: принято, 06.10.2026. Accepted SHA: `a65270a` (после него менялись только карточка и `todo.md`). Мержа не
требуется — работа в `dev` (D-22); `REVIEW → DONE`.

- Диапазон `36be42f..a65270a`: в коде только `image_cache_key_web_test.dart` — `pumpWidget(const SizedBox.shrink())` и
  `pumpAndSettle()` в конце двух тестов, которые строят `YuvImageWidget`. Временные `e65045b` (агрегат, `web.sh`) и
  `7c9f487` (контроль на `RawImage`) отменены `8c680ef` и `03a49fc` до Validation; `tool/ci/**`, `.github/**`,
  `lib/**`, `src/**` в итоговом диапазоне не изменены.
- DoD 1–2: R1 0/10 по SSH, R2 37359566518 воспроизвёл; L1 ×2 PASS, L2 ×2 (стандартный `RawImage`) воспроизвёл тот же
  ассерт — код пакета для сбоя не нужен, `lib/` не затронут (вывод отчёта, п. 2). Issue Flutter — не найдено. 4
  диагностических run по п. 8 — в лимите 6.
- DoD 3–6: 10/10 `all_web_test.dart --wasm` на Mac; локальные ключи `scope: all` exit 0, включая Linux VM; workflow
  37366114659 success на `a65270a`, `yuv-self-hosted`; `ci/all/CI-4` 9/9 success на `a65270a`, таблица времени есть,
  Web 26m36s против ~21m19s.
- DoD 7 (Reviewer): источники агрегата не убраны и не пропущены, retry нет, assertions не изменены — добавлен только
  teardown после них. Выполнено.
- Неточности отчёта, не блокирующие: «четыре временных коммита» — фактически два временных и два revert;
  `scope_guard.sh` запущен от `441229a`, а не от базы `36be42f` (код в обоих диапазонах тот же, результат `all`);
  строка «код `lib/` затронут: нет» дана по смыслу, а не дословно.

Blocking findings: нет.

Recommendations:
- `release/0.5.1` (`61da2ee`) не содержит исправлений тестов CI 3 и CI 4: Web CI на Mac для релизной ветки может
  упасть так же. Решить, переносить ли эти два тестовых изменения в `release/0.5.1` до выпуска.
- Web CI на Mac длиннее на ~5 мин (26m36s против ~21m19s на Windows); вывода о скорости не делалось — следить при
  следующих `ci/all`.
- Удалить теги `ci/*` пачкой в конце цикла (`todo.md`, правило 4).

Checks run by Reviewer: none.
