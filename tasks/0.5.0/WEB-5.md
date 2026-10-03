# WEB 5 — Web: причина расхождения шейдера и скорость показа
**Status:** IN_PROGRESS · **Tier:** T1 · **Owner:** Executor · **Depends On:** — · **Probe:** windows+pixel3 · **Base:** `12a7118`

#### Goal
WEB 1 выключила шейдер `YuvFrameRenderer` на Web: в CanvasKit (Chrome 154, headless) проба SHADER 3 дала
`max_diff=255` во **всех** 7 случаях (3x5, 33x17, 720x480, 1920x1080, padding, scale_x2, contain). Расхождение
одинаковое на всех размерах — это похоже на систематическую ошибку, а не на неточность GPU: формат или порядок каналов
при загрузке плоскостей в текстуру, premultiplied alpha, сэмплинг, чтение результата через `toImage` в CanvasKit.
Причину WEB 1 не искала. Шейдер на Web нужен (D-21).

Сначала оценка: что сейчас происходит на Web и как — какой путь показа, где расходится (по каналам, по пикселям, на
однотонном кадре), — и чем рискуем. Затем:
- найти причину расхождения; если её можно исправить — включить шейдер на Web обратно (снять выключатель `kIsWeb`),
  Web-проба проверяет `hasShader == true` и `max_diff <= 1`; если нельзя — причину в dartdoc и README;
- замерить показ на Web: 720p, кадров в секунду через BGRA-путь и через шейдер (если включён) — release-сборка
  (`flutter build web`). Базовые числа BGRA-пути уже есть (`doc/perf-findings.md`, «Web»); вывод — туда же.

Этап 7 (D-21), первый пул этапа; APPLE 1 — следующим пулом (D-25) и проверяет на Metal то, что изменит WEB 5.
Учитывает итог WEB 4 (`doc/web-camera-yuv.md`): на Web перевод 720p YUV → BGRA в WASM стоит ~38 мс, а источник
камеры перейдёт на исходный `NV12`, только если шейдер на Web заработает.

#### Architect Decision
1. **Renderer — CanvasKit** (по умолчанию для `flutter build web` на Flutter 3.44, Chrome на Windows). skwasm и
   `--wasm` в задачу не входят: их смоук — WEB 2. Если причина окажется общей для CanvasKit и skwasm, это пишется в
   вывод, но не проверяется.
2. **Порядок диагностики** — от грубого к точному, каждый шаг — временный харнесс, который не коммитится (проба
   SHADER 3 с отладочным выводом или отдельный `integration_test` вне `web.ps1`):
   1. включить шейдер на Web локально и снять расхождение **по каналам R, G, B, A отдельно** и по пикселям на одном
      маленьком случае (3x5, 33x17): весь кадр прозрачный или чёрный — шейдер не рисует или `toImage` не видит
      результат; разница только в RGB — данные или формула;
   2. **однотонный кадр** (Y=128, U=V=128 → ожидание серый 130): отделяет сэмплинг и координаты от данных;
   3. **альфа-контроль:** тот же кадр, но в упакованной текстуре 4-й байт каждого тексела = 255. Если расхождение
      исчезает — виновата premultiplied alpha (байты плоскостей лежат в канале A, CanvasKit/WebGL умножает на него
      RGB); на native такого нет;
   4. остальное — по результату: ориентация `FlutterFragCoord` (переворот по Y), порядок uniform-ов и sampler в
      CanvasKit, сэмплинг (`filterQuality`), формат `decodeImageFromPixels` с `rgba8888` на Web.
3. **Правки.** Разрешены `lib/src/widgets/yuv_frame_renderer.dart`, `lib/src/widgets/yuv_planes_texture.dart`,
   `shaders/yuv_frame.frag` и Web-проба. Исправление в общем коде (упаковка, шейдер) должно оставить native-пробу
   SHADER 3 на `max_diff <= 1`: Windows — Executor, Pixel 3 arm64 — Reviewer (отсюда `windows+pixel3`; Metal проверяет
   APPLE 1). Отдельная Web-ветка в упаковке или шейдере допустима, только если общая правка невозможна — причина в
   отчёте. Публичный API не меняется: `hasShader` по-прежнему значит «шейдер загружен».
4. **Негативный контроль:** после исправления временно испортить упаковку (например, поменять `u.offset` и
   `v.offset` местами) — Web-проба должна упасть; откатить. Результат — в отчёт.
5. **Замер скорости** — как WEB 8 (`git show 66b3fb4:tasks/0.5.0/WEB-8.md`): `flutter build web --release`
   (dart2js), Chrome на Windows, синтетический кадр 1280×720 I420 и NV12, 10 прогревов + 30 замеров, медианы в мс.
   Мерить `upload()` и полный кадр `upload()` + `paint()` + `toImage()`; к/с = 1000 / медиана полного кадра. Сравнение
   — BGRA-кадр и YUV через BGRA-путь (шейдер выключен) против YUV через шейдер. Харнесс не коммитится; вывод — строкой
   в `doc/perf-findings.md`, «Web».
6. **Включать шейдер на Web**, если выполнены оба условия: Web-проба `max_diff <= 1` во всех 7 случаях и полный кадр
   720p YUV через шейдер не медленнее YUV через BGRA-путь. Иначе — шейдер выключен, причина в dartdoc `load()` /
   `hasShader` и README.
7. **Камера example** на `NV12` не переводится: это решение по итогу, рекомендация — в `doc/web-camera-yuv.md`.

#### Scope
- `lib/src/widgets/yuv_frame_renderer.dart` — выключатель `kIsWeb` и dartdoc;
- `lib/src/widgets/yuv_planes_texture.dart`, `shaders/yuv_frame.frag` — если этого требует причина;
- `example/integration_test/shader_probe_web_test.dart` и при необходимости `helpers/shader_probe_cases.dart`;
  `tool/ci/web.ps1` — если меняется число случаев Web-пробы;
- `README.md` (Web), `CHANGELOG.md` (верхняя запись), `doc/perf-findings.md`, `doc/web-camera-yuv.md`.

#### Constraints
- `src/`, WASM-сборка, bindings, публичные сигнатуры, камерный источник example — не меняются.
- Native-проба SHADER 3 (Windows, Pixel 3) остаётся `max_diff <= 1`.
- Сырые замеры и диагностические харнессы не коммитятся.

#### Definition of Done
- Причина расхождения названа и подтверждена контролем из решения 2 (или доказано, что её нельзя устранить
  в CanvasKit, — с шагами, которые это показали).
- Либо шейдер на Web включён: `shader_probe_web_test.dart` проверяет `hasShader == true` и `max_diff <= 1` во всех
  7 случаях, негативный контроль падает; либо выключен с причиной в dartdoc и README.
- Числа скорости 720p (решение 5) — в `doc/perf-findings.md`; вывод для камеры — в `doc/web-camera-yuv.md`.
- CHANGELOG описывает изменение поведения на Web, если оно есть.

#### Validation
- Executor: `pwsh -File tool/ci/web.ps1`, `pwsh -File tool/ci/windows.ps1` (Windows-проба и native-проба шейдера),
  `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/example.ps1`; при правке упаковки или шейдера —
  `pwsh -File tool/ci/android.ps1`. Ключи — `bash tool/ci/scope_guard.sh <base>`.
- Reviewer: повтор Web-пробы и негативного контроля, Pixel 3 arm64 — `shader_probe_native_test.dart` при правке
  упаковки или шейдера; выборочный повтор замера.

#### Executor Report
#### Review
