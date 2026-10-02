# SHADER 2 — Шейдер и `YuvFrameRenderer`
**Status:** ACCEPTED · **Tier:** T2 · **Owner:** — · **Depends On:** GEOM 1, SHADER 1 · **Probe:** windows

#### Goal
По прототипу VIEW-04 (`example/shaders/view04_i420.frag`, `example/lib/view04_i420_shader.dart`): шейдер
`shaders/yuv_frame.frag` рисует текстуру SHADER 1 по `YuvFrameGeometry`; `YuvFrameRenderer` выбирает шейдер или
обычный BGRA-путь. Полная проба на платформах — SHADER 3.

Пул этапа 4 «показ кадров»: GEOM 1 → SHADER 1 → SHADER 2 → SHADER 3 → PRESENT 1.

#### Architect Decision
1. **API** — `lib/src/widgets/yuv_frame_renderer.dart`, экспорт в `lib/yuv_ffi.dart`:
   ```dart
   final class YuvFrameRenderer {
     static Future<YuvFrameRenderer> load();
     bool get hasShader;
     Future<YuvFrameTexture> upload(YuvImage frame);
     void paint(Canvas canvas, YuvFrameTexture texture, YuvFrameGeometry geometry);
     void dispose();
   }

   final class YuvFrameTexture {
     int get width;    // source frame size
     int get height;
     void dispose();
   }
   ```
   - `load()` грузит `packages/yuv_ffi/shaders/yuv_frame.frag`. Ошибка загрузки или Web (до WEB 1) — рендерер без
     шейдера (`hasShader == false`), всё идёт BGRA-путём. `hasShader` нужен, чтобы видеть, что шейдер реально
     работает: иначе отказ загрузки незаметен, кадры просто рисуются медленнее.
   - `upload` копирует кадр до первого `await` (dartdoc это обещает): шейдер есть и `YuvPlanesTexture.pack` не `null`
     → текстура из `pack().bytes` (`PixelFormat.rgba8888`); иначе `toBgraBytes()` (`PixelFormat.bgra8888`).
     Загрузка байтов в `ui.Image` — как `_decodeBgra` в `yuv_frame_presenter.dart`; общий код вынести в одну приватную
     функцию пакета, не копировать.
   - `paint`: размер текстуры ≠ `geometry.sourceSize` → `ArgumentError`. Клип по
     `destinationRect ∩ (Offset.zero & viewSize)`. Шейдер — `drawRect` с шейдером; BGRA —
     `canvas.transform(geometry.sourceToView.storage)` + `drawImage` (`FilterQuality.none` — оба пути дают одни и те же
     пиксели при любом масштабе, решение 6).
2. **Шейдер** — `shaders/yuv_frame.frag`, в `pubspec.yaml` → `flutter: shaders:`. Эталон (оформление можно менять,
   формулы — нет; не сжимать в строку: по выражению на строку, комментарии эталона сохранить):
   ```glsl
   #version 460 core
   precision highp float;

   #include <flutter/runtime_effect.glsl>

   uniform highp vec2 uFrameSize;    // W, H
   uniform highp vec2 uTextureSize;  // texture width, height
   // view -> source: sx = x*m00 + y*m01 + t0, sy = x*m10 + y*m11 + t1
   uniform highp vec4 uLinear;       // (m00, m10, m01, m11)
   uniform highp vec2 uTranslate;    // (t0, t1)
   uniform highp vec3 uU;            // row, offset, step
   uniform highp vec3 uV;
   uniform sampler2D uPlanes;

   out vec4 fragColor;

   float planeByte(highp float row, highp float byteIndex) {
     highp float texel = floor(byteIndex / 4.0);
     highp float channel = byteIndex - texel * 4.0;
     vec4 value = texture(uPlanes, (vec2(texel, row) + 0.5) / uTextureSize);
     vec4 mask = vec4(1.0) - min(abs(vec4(channel) - vec4(0.0, 1.0, 2.0, 3.0)), vec4(1.0));
     return floor(dot(value, mask) * 255.0 + 0.5);
   }

   void main() {
     highp vec2 p = FlutterFragCoord().xy;
     highp vec2 s = floor(vec2(p.x * uLinear.x + p.y * uLinear.z, p.x * uLinear.y + p.y * uLinear.w) + uTranslate);
     s = clamp(s, vec2(0.0), uFrameSize - 1.0);
     highp vec2 c = floor(s / 2.0);

     float y = planeByte(s.y, s.x);
     float u = planeByte(uU.x + c.y, uU.y + c.x * uU.z);
     float v = planeByte(uV.x + c.y, uV.y + c.x * uV.z);

     // BT.601 limited range as in src/yuv/abi/yuv_convert_v1.c: (k * value + 128) >> 8 == floor(k / 256 * value + 0.5).
     float yy = y - 16.0;
     float d = u - 128.0;
     float e = v - 128.0;
     float r = floor(1.1640625 * yy + 1.59765625 * e + 0.5);
     float g = floor(1.1640625 * yy - 0.390625 * d - 0.8125 * e + 0.5);
     float b = floor(1.1640625 * yy + 2.015625 * d + 0.5);
     fragColor = vec4(clamp(vec3(r, g, b), 0.0, 255.0) / 255.0, 1.0);
   }
   ```
3. **Uniform-ы** — `setFloat` по порядку объявления, 16 значений. Из `m = geometry.viewToSource.storage`:
   `m00 = m[0]`, `m10 = m[1]`, `m01 = m[4]`, `m11 = m[5]`, `t0 = m[12]`, `t1 = m[13]`.
   `setImageSampler(0, image, filterQuality: FilterQuality.none)`.
4. **Прототип VIEW-04** не трогать до DEVICE 1.
5. **Короткая проба** `example/integration_test/shader_probe_native_test.dart` (суффикс `_native_test` сам включает её
   в CI-скрипты всех native-платформ): I420 и NV12 `16x9`, шум из `helpers/probe/probe_seed.dart`, 8 ориентаций,
   масштаб 1:1. Ожидание — эталон решения 6 (функция в `example/integration_test/helpers/`, её же берут SHADER 3 и
   PRESENT 1); рисунок — `PictureRecorder` → `paint` → `toImage` → `toByteData(rawRgba)`. Допуск `max_diff <= 1` по
   каналу. Кадр `16x9` нечётной высоты оставить: на нём `apply()` и экран расходятся (решение 6).
6. **Контракт показа** (оба пути рендерера, dartdoc `paint`): пиксель view `(i, j)` внутри
   `destinationRect ∩ (Offset.zero & viewSize)` — это цвет пикселя `floor(transformPoint(viewToSource, (i + 0.5, j + 0.5)))`
   из `frame.toBgraBytes()`, с ограничением координат `[0, W−1] × [0, H−1]`; вне — прозрачный. Шейдер получает это
   формулой решения 2, BGRA-путь — построением. Эталон пробы считает ровно это в Dart.
   С `geometry.apply(frame)` не сравнивать: `apply()` создаёт новый 4:2:0 кадр и при нечётной стороне или нечётном
   начале видимой области пересчитывает U/V как среднее блока 2×2 (`yuv_kernel_v1.h`, visible re-encode; Q2 в
   `doc/api-abi-0.4-design.md`) — на шуме это до 220 уровней. Шейдер кадр не режет и не пересобирает, поэтому
   нечётная обрезка его не касается; формулы и 16 uniform-ов не меняются.
   Отклонены: усреднение блока в шейдере (больше uniform-ов, четыре чтения на пиксель, лишнее размытие цвета) и
   BGRA-путь для нечётных размеров (он показывает то же, что шейдер).

#### Scope
- `shaders/yuv_frame.frag`, `lib/src/widgets/yuv_frame_renderer.dart`, `pubspec.yaml`, `lib/yuv_ffi.dart`,
  `lib/src/widgets/yuv_frame_presenter.dart` (только вынос общей загрузки в `ui.Image`).
- `example/integration_test/shader_probe_native_test.dart`; VM `test/yuv_frame_renderer_test.dart`: BGRA-кадр идёт
  BGRA-путём; мутация `frame` сразу после `upload` не меняет результат; `paint` с чужим размером → `ArgumentError`.
- `README.md` (два предложения: когда шейдер, когда BGRA), `CHANGELOG.md`, `test/public_surface_test.dart`.

#### Constraints
- Native, `lib/src/yuv/impl/**`, интерфейс `YuvImage` и CI-скрипты не трогать.
- Если короткая проба не проходит — разбирать по вариантам SHADER 3 (решение 3 там).

#### Definition of Done
- [ ] API и шейдер — по решениям 1–3; поведение `YuvFramePresenter` не изменилось (его тесты проходят без правок).
- [ ] Короткая проба проходит на Windows и Android-эмуляторе (`max_diff` в отчёт); проба проверяет `hasShader == true`
      на native-платформах.

#### Validation
Ключи: `lib/*` → `vm example`, `shaders/*`, `pubspec.yaml`, `example/integration_test/*` → `all`.

- `dart format --line-length 150`; `flutter analyze` в корне и в `example/`.
- `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/windows.ps1`, `pwsh -File tool/ci/example.ps1`,
  `pwsh -File tool/ci/android.ps1`.
- Probe `windows`: в составе `tool/ci/windows.ps1`.

#### Executor Report
- Реализованы `YuvFrameRenderer`/`YuvFrameTexture`, shader asset и общий декодер `ui.Image`; BGRA fallback использует
  `FilterQuality.none`, а публичный контракт `paint` описывает выбор source-пикселя по центру view-пикселя.
- Короткая проба использует общий Dart-эталон решения 6 и LCG-шум из `probe_seed.dart`; I420/NV12 `16×9`, все восемь
  ориентаций: Windows и Android emulator — `hasShader == true`, во всех случаях `max_diff <= 1`.
- Таргетные renderer/presenter/public-surface тесты — 10 passed; `flutter analyze --no-fatal-infos` — без новых
  warnings/errors (58 существующих `library_annotations` info), `example` analyze — clean.
- `tool/ci/windows.ps1` — probe 20/20 (1 expected skip), reference 134/134, release build и три integration targets
  passed. `tool/ci/android.ps1` — split APK/ABI checks и три integration targets на API 35 emulator passed.
#### Review
Architect, 02.10.2026: `ARCHITECT_REQUIRED` снят — решение 6 (контракт показа); решение 1 — BGRA-путь с
`FilterQuality.none`, решение 5 — эталон по решению 6. В работе Executor остаётся заменить эталон пробы и фильтр
BGRA-пути и оформить шейдер по решению 2.
Ревью 02.10.2026:
```text
Pool: STAGE4-VIEW; SHADER 2
Outcome: ACCEPTED
Reviewed-Head: 7f4425c
Merged-Head: none (слияние — вместе с пулом)
Fixed: none
Blocking: none
Advisory: проба рисует через PictureRecorder без трансформации холста; случай со сдвигом/масштабом холста (позиция
  виджета, DPR) не покрыт — на Skia FlutterFragCoord() — это gl_FragCoord; на устройстве это проверит DEVICE 1.
```
Решения 1–6 выполнены: 16 uniform-ов, `FilterQuality.none` в BGRA-пути, общий декодер, эталон решения 6, шейдер
оформлен по образцу. Перепрогон Reviewer 02.10.2026: `flutter test` patch/presenter/renderer/public_surface — 22 passed; `example/` `flutter test` — 34 passed, `flutter analyze` — no issues.
