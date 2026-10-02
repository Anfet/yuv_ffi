# WEB 6 — Веб-камера: формат кадра и стоимость `copyTo`
**Status:** TODO · **Tier:** T1 · **Owner:** — · **Depends On:** — · **Probe:** none

#### Goal
Подсистема захвата из исследования WEB 4. Web-источник камеры
(`example/lib/camera/impl/yuv_camera_frame_source_web.dart`) читает кадр через `MediaStreamTrackProcessor` и
`VideoFrame.copyTo()` с `format: 'BGRA'` (запасной — `RGBA`). Выяснить, что отдаёт `copyTo` **без** `format` на
реальных камерах и сколько стоит каждый вариант `copyTo`. Импорт и показ — WEB 7 и WEB 8, вывод — WEB 4.

Пул `PAR-WEB`, идёт параллельно WEB 7 и WEB 8.

#### Architect Decision
1. **Прототип** — `example/lib/web_camera_capture_probe_main.dart`, отдельная точка входа на `package:web` по образцу
   Web-источника. **Не коммитится**. Сборка — release, в свой каталог (сборки параллельных карточек не пересекаются):
   `cd example && flutter build web --release -t lib/web_camera_capture_probe_main.dart -o build/web-web6`; отдача —
   статический сервер из `example/build/web-web6`. Результат — строка `WEB6 RESULT <json>` в консоль **и** на
   страницу (текстовое поле и кнопка «Копировать»).
2. **Что снимает.**
   - `getUserMedia({video: {width: {ideal: 1280}, height: {ideal: 720}}})`; фактическое разрешение — в результат.
   - Факты первого кадра: `format`, `codedWidth/Height`, `visibleRect`, `displayWidth/Height`, `allocationSize()`
     без опций, `PlaneLayout[]` (`offset`, `stride`), которые вернул `copyTo(buffer)` без `format`.
   - Стоимость: 10 кадров прогрева, затем 60. На каждом кадре три `copyTo` — без `format`, `BGRA`, `RGBA`; порядок
     сдвигается по кругу от кадра к кадру; время — `performance.now()` вокруг `await copyTo`; кадр закрывается.
     В результат — медиана и p90 по каждому варианту.
3. **Где снимать** (по порядку; следующий — только если предыдущий недоступен, причина — в отчёт):
   1. Реальная камера на Windows (эта машина), Chrome **не headless**, с `--use-fake-ui-for-media-stream`.
   2. Реальная камера на Mac (`todo.md`, «Окружение → Mac»): Chrome через `mac-run.sh` с
      `--use-fake-ui-for-media-stream`. Если через SSH камеры нет (`NotAllowedError`/`NotReadableError` или ни одного
      кадра за 10 с — разрешение macOS на камеру выдаётся только локальному запуску) — `AWAITING_EXTERNAL`: страницу
      открывает Engineer на Mac локально. В отчёт: команды сборки и отдачи, URL, что нажать, какую строку прислать.
   3. Фейковая камера Chrome на Windows (`--use-fake-device-for-media-stream`) — снимается всегда, только факты;
      её время в выводы не идёт.
   Нужна хотя бы одна реальная камера. Если доступны обе — оба набора.
4. **Ожидаемые исходы `copyTo` без `format`:** `I420`/`NV12` — норма; другой YUV (`I420A`, `I422`, `I444`, `NV12A`)
   — записать; RGB-формат или `format == null` — записать «исходного YUV нет»; `copyTo` бросает — текст ошибки.
   Каждый исход — результат, не провал задачи.

#### Scope
- Только раздел `#### Executor Report` этой карточки. Прототип — вне коммита.

#### Constraints
- `lib/`, native, Web-источник камеры и шейдер не менять. Только Chrome; `--wasm` не входит.
- Параллельно с WEB 7 и WEB 8 в одной копии: не переключать ветку, коммитить только свою карточку
  (`git commit -- tasks/0.5.0/WEB-6.md`), чужие файлы не трогать.

#### Definition of Done
- [ ] Строки `WEB6 RESULT` для фейковой камеры и хотя бы одной реальной — в отчёте целиком.
- [ ] Для каждой камеры: ОС, Chrome (версия), модель камеры, фактическое разрешение.
- [ ] Прототипа нет в коммитах; свои временные файлы удалены.

#### Validation
Ключи: `tasks/*` → —. Ветка `all/PAR-WEB` в основной копии (D-22). CI-скрипты не нужны.

#### Executor Report
#### Review
