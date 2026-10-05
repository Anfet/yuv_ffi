# CI 3 — Camera smoke в Web CI на Mac
**Status:** TODO · **Tier:** T2, Reviewer T1 · **Owner:** Executor · **Depends On:** — · **Probe:** none

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

6. **Решение Architect по `ENGINEER_REQUIRED` (05.10.2026).** Падение `all_web_test.dart --wasm` (Skwasm `Picture
   was disposed`, run 37336100554) — другая причина (п. 4): отдельная карточка CI 4. Camera smoke в workflow на Mac
   прошёл в том же run, поэтому DoD 5 сужен до camera smoke; зелёный workflow целиком и `ci/all` (DoD 6, п. 5)
   перенесены в CI 4. Executor: отчёт уже покрывает DoD 1–5 и 7 — перевести карточку в `REVIEW`.

#### Scope

`example/integration_test/camera_source_web_smoke_test.dart`; по варианту A2 —
`example/lib/camera/impl/yuv_camera_frame_source_web.dart`. Для разрешённой Engineer диагностики временно также
`example/test_driver/integration_test.dart` и `tool/ci/drive.sh`, чтобы передавать permission state и ход
`initialize()` в логи Actions при успехе и провале. Отчёт и статус — карточка и `todo.md`.

#### Constraints

- `lib/**`, `src/**`, `assets/wasm/**`, `tool/wasm/**` не менять.
- `tool/ci/**` и `.github/**` не менять, кроме варианта, явно согласованного Engineer через `ENGINEER_REQUIRED`.
- Не отключать, не пропускать и не повторять camera smoke ради зелёного прогона; не менять остальные тесты.
- Службы и метки раннера не трогать. На Mac работать во временном клоне; клон удалить после работы.
- `release/0.5.1` не менять.
- Engineer 05.10.2026 явно разрешил временную инструментализацию camera smoke/driver и целевой вывод диагностики
  через `drive.sh`, а также diagnostic GitHub Actions runs. Assertions сохранять; исходный таймаут оставить до замера
  задержки `initialize()`, затем менять только по результатам измерения.

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
5. Camera smoke проходит в workflow на Mac — check: run `ci-web.yml` на SHA с исправлением, раннер `yuv-self-hosted`;
   цель `camera_source_web_smoke_test.dart` — `PASS` в логе run (провал другой цели не относится к этой карточке, п. 6)
   — by: Executor
6. Перенесён в CI 4 (зелёный workflow целиком и `ci/all` с замером времени, п. 6 Architect Decision).
7. Проверки не ослаблены — check: чтение diff теста против п. 3 Architect Decision (непустой кадр, отсутствие кадров
   после `dispose`, нет `skip`/retry, таймаут изменён только с замером) — by: Reviewer

#### Validation

Минимум: DoD 1–4 локально (Mac и Windows), 5 — один запуск workflow, 6 — один `ci/all` после остального. Пробы по
`AGENTS.md`: пути карточки — `example/` → `none`. Теги `ci/*` — триггеры; удаляются пачкой в конце цикла (`todo.md`,
правило 4). Если `ci/all` упал вне Web — факт-карточка по `ci.md`, без диагноза.

#### Engineer Decision

05.10.2026: Engineer подтвердил, что крышка Mac была открыта во время R2 (`37315543986`); сбой повторился, значит крышка не объясняет проблему. Разрешил временную диагностику permission и фаз/длительности `initialize()` в smoke test с передачей результата через integration driver и `tool/ci/drive.sh`, а также diagnostic GitHub Actions runs. После R3 (`37330897047`) разрешил A1: таймаут 60 секунд, assertions сохранить. Диагностический код после измерений удалён.
#### Executor Report

Validated at: bdc0160
1. R1 до изменения — `bash tool/ci/drive.sh integration_test/camera_source_web_smoke_test.dart web-server --browser-name=chrome --headless --web-browser-flag=--use-fake-device-for-media-stream --web-browser-flag=--use-fake-ui-for-media-stream` (Mac, SSH) — 10/10 `All tests passed`; `initialize()` 79–86 ms (10/10).
2. GitHub Actions diagnostic run [37330897047](https://github.com/Anfet/yuv_ffi/actions/runs/37330897047), SHA `c3a9b34`: permission=`granted`; найден `fake_device_0`; `availableCameras()` занял 2704 ms; через 24 386 ms тест всё ещё ждал `controller.initialize()`, после teardown возник use-after-dispose. Диагностика подтверждает задержку fake-camera initialization на runner, а не отсутствие камеры или permission.
3. После A1 — smoke test на Mac 10/10 прошёл; финальный повтор на `bdc0160`: `MAC_FINAL_SMOKE failures=0/10`.
4. `bash tool/ci/web.sh` на Mac и `pwsh -File tool/ci/web.ps1` на Windows, итоговый код — оба exit 0 и `Web CI passed`; camera smoke включён, integration cases=64, reference matrix=119. `bash tool/ci/scope_guard.sh ea5eeda69a5c45fd664cacc15756e838131a228a` — `scope: all` (ключ для `example/integration_test/*`).
5. Повторный GitHub Actions run [37336100554](https://github.com/Anfet/yuv_ffi/actions/runs/37336100554), SHA `8fb5223`: camera smoke прошёл; permission=`granted`, `fake_device_0`, initialize=3795 ms, `testPassed=true`. Полный workflow завершился exit 1 позднее в `integration_test/all_web_test.dart`: Skwasm `The native object of Picture was disposed` (`native_memory.dart:112`, `!isDisposed`), длительность 22m12s. Это отдельное падение, которое в CI-3 не исследовалось.
6. `ci/all/CI-3` не запускался: DoD 5 не зелёный из-за отдельного Web integration failure.
7. Проверка diff: в camera smoke изменён только timeout с 15 до 60 секунд; проверки кадра и отсутствия кадров после `dispose` сохранены, `skip` и retry отсутствуют. Временная диагностика удалена.
Deviations: DoD 5 не пройден полностью, поэтому DoD 6 (`ci/all`) не запускался. Нужна отдельная карточка/решение Engineer по падению `all_web_test.dart`; причина в CI-3 не диагностировалась.

#### Review

—
