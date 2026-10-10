# yuv_ffi — принятые задачи

Одна запись на принятую задачу: что сделано, SHA слияния, run CI. Карточка после приёмки удаляется, история — в git.

История прошлых циклов удалена из рабочего дерева и доступна в git:

- **0.5.0** — выпущена 05.10.2026, тег `0.5.0` на `3e4c645`: принятые задачи, CI-прогоны и аудит —
  `git show b160704:COMPLETION.md`, `git show b160704:doc/release-0.5.0-audit.md`.
- **0.4.2** — закрыта без выпуска 01.10.2026: `git show 6ab8948:<путь>`.

## Цикл 0.5.2

- **YUV 1** — DONE: после принятого G1 CAM 3 удалены перенесённые камера/ML Kit, зависимости и камерные настройки из примера YUV; редактор сохранил C5 (crop/Negate/Reset), YUV targets и Web-матрицы сохранены; регистрант macOS пересоздан, iOS Podfile сохранён. Base `a4fb1ff725d5cba35e2d789362867123d1100e27`; accepted SHA `7e0f6c03e6a4820304341bf2bcecb1fb55573433`. Windows-local vm/windows/android/web/example/smoke PASS по Executor Report; Mac/iOS/Linux/device gate — этап 2. CI не требуется по D-38; удаление workflows — CI 1; merge/push не требуются. Карточка и Review 2: group `git show 6d23636:tasks/0.5.2/YUV-1.md`.
- **YUV 2** — DONE: версия 0.5.2 в pubspec, верхней записи CHANGELOG, podspec и src/CMakeLists.txt (только metadata); README/CHANGELOG описывают вынос камеры в `yuv_camera`, web-parity больше не считает camera Web smoke YUV-доказательством. Base `edc596c02f7fcee348201f015f071eda4001ae0b`; accepted SHA `fa48e3b303763c6ae03db050445dbb965b0f2fba`. Windows-local vm/windows/android/web/example/smoke, probe/reference, CTest PASS по Executor Report; Pixel 3 RA-25 arm64 и armv7 smoke/probe PASS (Reviewer); Mac/iOS/Linux — этап 2. CI не требуется по D-38; merge/push не требуются. Карточка и Review 1: group `git show 58080e1:tasks/0.5.2/YUV-2.md`.

## Цикл 0.5.1

- **RELEASE 1** — 0.5.1 выпущена 07.10.2026 по команде Engineer: pub.dev подтвердил публикацию, аннотированный тег `0.5.1`, `main` и `release/0.5.1` на принятом SHA `2287a8efa636141914d25b844b279d4dd77d4b3d`; `main` — предок `dev`, CI-теги очищены. Свежий CI `ci/all/0.5.1-2` 9/9 success (Web run 37544596027), Pixel 3 arm64/armv7 по 1188 PASS, pana 160/160, публикация exit 0. Ревью: `git show 6594930:tasks/0.5.1/RELEASE-1.md`.
- **FIX 1** — README приведён к фактическому статусу Web и платформ, версия `0.5.1` в файлах D-14 и `example/pubspec.lock`; первоначально принято на `1866a2d`, Pixel 3 arm64/armv7 1188/1188, CI: `ci/web/WASM` run 37243974376 — success (карточка: `git show 2651ebd:tasks/0.5.1/FIX-1.md`). Повторно принято 07.10.2026 на `302c75f`: четыре документа согласованы по Web JavaScript/`--wasm` в Chrome и миграции 0.5.x; переносимый коммит `de5a5df`, Probe: none, CI: не требуется; гейт нового кандидата — RELEASE 1. Ревью: `git show a336929:tasks/0.5.1/FIX-1.md`.
- **WEB 4** — interop Web backend исправлен для `flutter build web --wasm`: probe 1188, reference 119, шейдер и `all_web_test.dart` проходят в Chrome. Принято на `1866a2d`; CI: `ci/web/WASM` run 37243974376 — success. Карточка: `git show 2651ebd:tasks/0.5.1/WEB-4.md`.
- **CI 1** — Web CI требует обязательный прогон probe, shader probe и all Web tests с `--wasm`. Принято на `1866a2d`; run 37243974376 — success.
- **CI 2** — Web CI (`ci-web.yml`) перенесён на Mac `yuv-self-hosted` через `tool/ci/web.sh`; `web.ps1` остался локальной проверкой Windows. Принято на `754bbdd` по D-32 (DoD 7 засчитан, DoD 8 перенесён); CI: run 37301435314 — failure в camera smoke. Карточка: `git show 6572c18:tasks/0.5.2/CI-2.md`.
- **CI 3** — camera smoke в Web CI на Mac: причина — медленный `initialize()` fake-камеры на раннере, таймаут теста 60 с по замеру. Принято на `bdc0160`; CI: run 37336100554 — camera smoke PASS. Карточка: `git show 3e0f0ea:tasks/0.5.2/CI-3.md`.
- **CI 4** — Skwasm `Picture was disposed` в `all_web_test.dart --wasm` на Mac: teardown виджет-тестов `image_cache_key_web_test.dart`, `lib/` не затронут. Принято на `a65270a`; CI: `ci/all/CI-4` 9/9 success, Web run 37370821880. Карточка: `git show 3e0f0ea:tasks/0.5.2/CI-4.md`.
