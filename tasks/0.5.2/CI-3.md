# CI 3 — Camera smoke в Web CI на Mac
**Status:** ENGINEER_REQUIRED · **Tier:** T2, Reviewer T1 · **Owner:** Engineer · **Depends On:** — · **Probe:** none

**Base SHA:** ea5eeda69a5c45fd664cacc15756e838131a228a (SHA `dev` на старте карточки)

#### Goal

Web CI на Mac (`ci-web.yml`, раннер `yuv-self-hosted`) зелёный. После карточки причина падения
`camera_source_web_smoke_test.dart` в run 37301435314 установлена и подтверждена воспроизведением, исправление
устраняет её без ослабления проверок, и выполнены два пункта, перенесённые из CI 2 по D-32: зелёный workflow на Mac
и замер времени `ci/all`. Карточка идёт до выпуска 0.5.1 (D-31, D-32); `release/0.5.1` (`61da2ee`) она не меняет.

#### Diagnosis

Факты на 05.10.2026; нужны только на старте.

- Run 37301435314 (`51eb041`, `yuv-self-hosted`): сборка WASM, dry-run, браузерная матрица (14 источников) и
  reference `--profile` прошли; упал `camera_source_web_smoke_test.dart` («fake Web camera delivers a non-empty frame
  and stops cleanly»); цели `--wasm` после него не запускались. Ошибка — единственная в выводе:
  `A CameraController was used after being disposed.`, стек `package:camera/src/camera_controller.dart 361:7` →
  `set value`.
- `camera` 0.11.0+2, `camera_web` 0.3.5 (`example/pubspec.lock`). Строка 361 — `value = value.copyWith(isInitialized:
  true, ...)` в конце `_initializeWithDescription`, то есть `controller.initialize()` завершился **после**
  `controller.dispose()`. `dispose()` (строка 876) сразу помечает контроллер освобождённым и только потом ждёт
  `_initializeFuture`.
- Тест (`example/integration_test/camera_source_web_smoke_test.dart`): `addTearDown(controller.dispose)`, затем
  `await controller.initialize()`, затем `YuvCameraFrameSource.start()` и ожидание кадра до 100 × 100 мс; таймаут теста —
  15 с. Если `initialize()` не успевает за 15 с, тест прерывается по таймауту, teardown вызывает `dispose()`, и
  поздний `initialize()` даёт именно эту ошибку. Это гипотеза H1, не проверена.
- H2: Web-источник примера (`example/lib/camera/impl/yuv_camera_frame_source_web.dart`) открывает собственный
  `getUserMedia` параллельно с потоком `camera_web`; под службой раннера (launchd, без интерактивной сессии) доступ к
  камере может вести себя иначе, чем по SSH.
- Тот же тест прошёл: на Windows в `ci/all/0.5.1` (run 37286266838) и на Mac в локальном прогоне `bash tool/ci/web.sh`
  Executor CI 2 по SSH. Падение известно только в workflow на Mac, один раз из одного запуска.
- `tool/ci/drive.sh` при провале печатает вывод с первой строки `FAILED|EXCEPTION|Error`, поэтому предшествующие
  строки (например, сообщение о таймауте) в лог run не попадают. Полный вывод — только при локальном запуске
  `flutter drive`.
- Время для сравнения в DoD 6: последний `ci/all` до переноса — `ci/all/0.5.1`, Web run 37286266838 (Windows,
  08:51:35 → 09:12:54, ~21 мин).

#### Architect Decision

1. **Сначала воспроизвести, потом чинить.** Порядок:
   - R1 — на Mac по SSH, в чистом клоне на SHA `dev`: только camera smoke, 10 раз подряд (команда в DoD 1), с полным
     выводом `flutter drive` в файл. Записать число падений и время `initialize()` (временный замер в клоне, не коммитится).
   - R2 — если R1 даёт 0 падений из 10: один `gh workflow run ci-web.yml --ref dev` на базовом SHA. Падение в
     workflow при 0/10 по SSH подтверждает зависимость от контекста службы раннера (H2 или окружение).
   - Если не воспроизводится ни R1, ни R2 — `ENGINEER_REQUIRED`: «разовый сбой; варианты — закрыть карточку с
     записью в `doc/perf-findings.md` или оставить наблюдение до следующего падения; рекомендация — закрыть, если
     DoD 5 и 6 зелёные». Код не менять.
2. **Исправление — первый вариант, который прошёл Validation.** Отвергнутые варианты — с логами в отчёте.
   - A1 (H1, гонка теста): тест не оставляет `initialize()` незавершённым к teardown — например, `dispose()` ждёт
     завершения инициализации, а время инициализации укладывается в таймаут. Увеличение таймаута допустимо только
     с замером из R1/R2 (фактическое время инициализации и запас ×2), не «на глаз».
   - A2 (H2, источник примера): исправление в `example/lib/camera/impl/yuv_camera_frame_source_web.dart` или порядке
     захвата камеры в тесте, если R1/R2 показали конфликт двух `getUserMedia`. Публичный пакет (`lib/`) не меняется.
   - A3 (окружение раннера): если причина — права службы раннера, Chrome-профиль или флаги запуска, которые
     `web.sh` не может задать, — `ENGINEER_REQUIRED` с вопросом и рекомендацией; службы раннера не трогать.
3. **Проверки не ослабляются.** Тест по-прежнему требует непустой кадр с ненулевыми байтами и отсутствие новых
   кадров после `source.dispose()`. Camera smoke не пропускается и не отключается в `web.sh`/`web.ps1`; повтор
   упавшего теста (retry) не вводится.
4. **Другие падения.** Если в R1/R2 или в DoD 5–6 падает другая цель — записать факт (SHA, run/job, цель, фрагмент
   ошибки) в отчёт. Та же причина — чинится здесь же; другая — `ENGINEER_REQUIRED` с предложением отдельной
   карточки, без диагноза за пределами camera smoke.
5. **Время `ci/all`** (из CI 2, п. 7). Записать таблицу «workflow → run → длительность» и сравнить Web с run
   37286266838. Если `ci/all` стал неприемлемо длиннее — `ENGINEER_REQUIRED` с цифрами, а не откат по своему решению.

#### Scope

`example/integration_test/camera_source_web_smoke_test.dart`; по варианту A2 —
`example/lib/camera/impl/yuv_camera_frame_source_web.dart`. Отчёт и статус — карточка и `todo.md`.

#### Constraints

- `lib/**`, `src/**`, `assets/wasm/**`, `tool/wasm/**` не менять.
- `tool/ci/**` и `.github/**` не менять, кроме варианта, явно согласованного Engineer через `ENGINEER_REQUIRED`.
- Не отключать, не пропускать и не повторять camera smoke ради зелёного прогона; не менять остальные тесты.
- Службы и метки раннера не трогать. На Mac работать во временном клоне; клон удалить после работы.
- `release/0.5.1` не менять.

#### Definition of Done

1. Воспроизведение до исправления записано — check: на Mac в чистом клоне базового SHA при запущенном
   `~/bin/chromedriver --port=4444` 10 раз
   `bash tool/ci/drive.sh integration_test/camera_source_web_smoke_test.dart web-server --browser-name=chrome --headless --web-browser-flag=--use-fake-device-for-media-stream --web-browser-flag=--use-fake-ui-for-media-stream`;
   в отчёте — «падений N из 10», фрагмент полного вывода упавшего прогона и время `initialize()` (временный
   замер во временном клоне, не коммитится); при 0/10 — run
   R2 с результатом, или `ENGINEER_REQUIRED` по п. 1 — by: Executor
2. Причина названа и связана с доказательством — check: отчёт — H1, H2 или другая причина; ссылка на вывод
   из DoD 1 или run R2, который её показывает; выбранный вариант A1/A2 и логи отвергнутых — by: Executor
3. После исправления camera smoke стабилен на Mac — check: та же команда, что в DoD 1, 10 раз на SHA карточки →
   10 из 10 `All tests passed`, exit 0 — by: Executor
4. Локальные проверки по ключам — check: `bash tool/ci/scope_guard.sh <base>` (для `example/integration_test/*` —
   `all`) и команды из `AGENTS.md` для каждого ключа, доступного на машинах; в том числе Mac `bash tool/ci/web.sh` →
   exit 0 и строка `Web CI passed: ...` и Windows `pwsh -File tool/ci/web.ps1` → exit 0 и строка `Web CI passed: ...`;
   по каждому ключу — exit code — by: Executor
5. Workflow на Mac зелёный — check: `gh workflow run ci-web.yml --ref dev`, затем
   `gh run watch <run-id> --exit-status` → exit 0; `gh run view <run-id> --json headSha,jobs --jq '.headSha, .jobs[].runnerName'`
   → SHA карточки и `yuv-self-hosted` — by: Executor
6. `ci/all` на SHA карточки 9/9 и время записано — check: тег `ci/all/CI-3` на SHA карточки; все 9 run `success`,
   `headSha` = SHA карточки; в отчёте таблица «workflow → run → длительность» и сравнение Web с run 37286266838 —
   by: Executor
7. Проверки не ослаблены — check: чтение diff теста против п. 3 Architect Decision (непустой кадр, отсутствие кадров
   после `dispose`, нет `skip`/retry, таймаут изменён только с замером) — by: Reviewer

#### Validation

Минимум: DoD 1–4 локально (Mac и Windows), 5 — один запуск workflow, 6 — один `ci/all` после остального. Пробы по
`AGENTS.md`: пути карточки — `example/` → `none`. Теги `ci/*` — триггеры; удаляются пачкой в конце цикла (`todo.md`,
правило 4). Если `ci/all` упал вне Web — факт-карточка по `ci.md`, без диагноза.

#### Executor Report

Validated at: ea5eeda69a5c45fd664cacc15756e838131a228a
1. R1 до исправления — `bash tool/ci/drive.sh integration_test/camera_source_web_smoke_test.dart web-server --browser-name=chrome --headless --web-browser-flag=--use-fake-device-for-media-stream --web-browser-flag=--use-fake-ui-for-media-stream` (Mac, временный клон базового SHA) — 10/10 `All tests passed`; дополнительный замер тем же способом: `initialize()` 79–86 ms (10/10).
2. Диагноз — R1: 10/10 успешны, H1 на SSH не воспроизведён; run [37306746524](https://github.com/Anfet/yuv_ffi/actions/runs/37306746524), head SHA `754bbdddeb625ba17b094e7ba3b9a7ce9bb2d6552`, упал на camera smoke тем же `A CameraController was used after being disposed` из `camera_controller.dart:361`. Ошибка подтверждает H1-механизм: инициализация завершилась после `dispose()`. R2 не показывает её фактическую длительность; локальный замер 79–86 ms не объясняет runner-сбой. H2 исключён порядком теста: собственный `getUserMedia` источника вызывается только после `controller.initialize()`. A1 нельзя выбирать без длительности из runner; A2 не соответствует месту сбоя. Дальше требуется решение Engineer по A3/контексту GitHub Mac runner вне Scope.
3. Постфиксные 10 прогонов — не запускались: исправление не выбрано до решения Engineer.
4. Локальные проверки `all` на Mac/Windows и `web.ps1` — не запускались: остановка по A3; `scope_guard.sh ea5eeda...` сообщил `scope: none`.
5. `ci-web.yml` — `gh run watch 37306746524 --exit-status` — exit 1; Mac workflow упал на camera smoke, run head SHA не совпадает с SHA карточки.
6. `ci/all/CI-3` — не запускался: нужен зелёный DoD 5 на SHA карточки.
7. Не ослаблены проверки — код не менялся; итоговую проверку diff выполняет Reviewer после решения Engineer.
Deviations: остановлено на A3 согласно Architect Decision.
Engineer attention: требуется решить, разрешить ли отдельную работу над контекстом Chrome/camera на Mac runner (права, профиль или запуск службы) либо отложить CI 3 до устранения этого ограничения; рекомендация — не менять таймаут по SSH-замеру 79–86 ms; сначала решить, кто и в какой задаче исследует контекст Mac runner.

#### Review

—
