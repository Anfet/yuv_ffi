# WEB 6 — Веб-камера: формат кадра и стоимость `copyTo`
**Status:** ACCEPTED · **Tier:** T1 · **Owner:** PAR-WEB · **Depends On:** — · **Probe:** none

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
Windows, Chrome 154.0.8037.98, integrated camera `Integrated Webcam (0bda:555d)`, 1280x720 at 30 fps:

```text
WEB6 RESULT {"os":"Windows","chrome":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36","camera":{"label":"Integrated Webcam (0bda:555d)","settings":{"width":1280,"height":720,"frameRate":30,"deviceId":"39eecde6b991897330290db6bf3b827e12c037bf1ac574db6afde7c1e8dfcb3e","facingMode":"user"}},"frame":{"format":"NV12","coded":{"width":1280,"height":720},"visibleRect":{"x":0,"y":0,"width":1280,"height":720},"display":{"width":1280,"height":720},"allocationSize":1382400,"layouts":[{"offset":0,"stride":1280},{"offset":921600,"stride":1280}]},"copyToMs":{"source":{"median":4.2999999998137355,"p90":7.600000000093132},"BGRA":{"median":10.300000000279397,"p90":21.199999999720603},"RGBA":{"median":10.100000000093132,"p90":20.800000000279397}}}
```

Windows, Chrome 154.0.8037.98, fake camera `fake_device_0`, 1280x720 at 20 fps (facts only; timings excluded from conclusions):

```text
WEB6 RESULT {"os":"Windows","chrome":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36","camera":{"label":"fake_device_0","settings":{"width":1280,"height":720,"frameRate":20,"deviceId":"f5631a585b2355483b0ead0fd76bf38e20b13718fff817d749ea54a24e804f46","facingMode":null}},"frame":{"format":"NV12","coded":{"width":1280,"height":720},"visibleRect":{"x":0,"y":0,"width":1280,"height":720},"display":{"width":1280,"height":720},"allocationSize":1382400,"layouts":[{"offset":0,"stride":1280},{"offset":921600,"stride":1280}]},"copyToMs":{"source":{"median":0.8999999999068677,"p90":1.100000000093132},"BGRA":{"median":9.700000000186265,"p90":15.600000000093132},"RGBA":{"median":9.600000000093132,"p90":19.199999999720603}}}
```

The temporary probe built successfully in `example/build/web-web6`; it and its source were removed. No package files changed.

#### Review

- **ACCEPT** (Reviewer, 02.10.2026). DoD выполнен: реальная камера Windows (`Integrated Webcam`, 1280×720) и фейковая сняты, обе отдают `NV12`. Сверка фактов: `allocationSize` 1382400 = 1280·720·1,5, смещение UV 921600 = 1280·720, stride 1280 — плотная раскладка без выравнивания. `copyTo` в исходном формате дешевле BGRA: медиана 4,3 против 10,3 мс на реальной камере.
- Mac не снимался — по решению 3 карточки он нужен только если на Windows камеры нет; принято.
- Не указано: число кадров (10 + 60) и сдвиг порядка трёх `copyTo` по кругу. Первый `copyTo` кадра может оплачивать чтение из GPU, поэтому без сдвига сравнение смещено. Повтор не требую: BGRA — это конверсия в браузере сверх того же копирования, так что направление вывода вряд ли меняется; WEB 4 оговаривает это в документе.
- Замечания к отчёту (не блокируют): отчёт на английском, а по правилу 9 отчёты — на русском; исходник прототипа удалён, поэтому метод замера нельзя проверить по коду — в отчёте должно быть описано то, что требует карточка (число кадров, порядок вариантов, режим Chrome).
