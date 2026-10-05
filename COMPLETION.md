# yuv_ffi — принятые задачи

Одна запись на принятую задачу: что сделано, SHA слияния, run CI. Карточка после приёмки удаляется, история — в git.

История прошлых циклов удалена из рабочего дерева и доступна в git:

- **0.5.0** — выпущена 05.10.2026, тег `0.5.0` на `3e4c645`: принятые задачи, CI-прогоны и аудит —
  `git show b160704:COMPLETION.md`, `git show b160704:doc/release-0.5.0-audit.md`.
- **0.4.2** — закрыта без выпуска 01.10.2026: `git show 6ab8948:<путь>`.

## Цикл 0.5.1

- **FIX 1** — README приведён к фактическому статусу Web и платформ, версия `0.5.1` в файлах D-14 и `example/pubspec.lock`. Принято на `1866a2d`; Pixel 3 arm64/armv7 1188/1188; CI: `ci/web/WASM` run 37243974376 — success. Карточка: `git show 2651ebd:tasks/0.5.1/FIX-1.md`.
- **WEB 4** — interop Web backend исправлен для `flutter build web --wasm`: probe 1188, reference 119, шейдер и `all_web_test.dart` проходят в Chrome. Принято на `1866a2d`; CI: `ci/web/WASM` run 37243974376 — success. Карточка: `git show 2651ebd:tasks/0.5.1/WEB-4.md`.
- **CI 1** — Web CI требует обязательный прогон probe, shader probe и all Web tests с `--wasm`. Принято на `1866a2d`; run 37243974376 — success.
- **CI 2** — Web CI (`ci-web.yml`) перенесён на Mac `yuv-self-hosted` через `tool/ci/web.sh`; `web.ps1` остался локальной проверкой Windows. Принято на `754bbdd` по D-32 (DoD 7 засчитан, DoD 8 перенесён); CI: run 37301435314 — failure в camera smoke. Карточка: `git show 6572c18:tasks/0.5.2/CI-2.md`.
