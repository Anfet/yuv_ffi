# SHADER 2 — Шейдер и `YuvFrameRenderer`
**Status:** BLOCKED · **Tier:** T2 · **Owner:** SHADER 1 · **Depends On:** GEOM 1, SHADER 1 · **Probe:** windows

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
     `canvas.transform(geometry.sourceToView.storage)` + `drawImage` (`FilterQuality.low`).
2. **Шейдер** — `shaders/yuv_frame.frag`, в `pubspec.yaml` → `flutter: shaders:`. Эталон (оформление можно менять,
   формулы — нет):
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
   масштаб 1:1. Ожидание — `geometry.apply(frame).toBgraBytes()`; рисунок — `PictureRecorder` → `paint` →
   `toImage` → `toByteData(rawRgba)`. Допуск `max_diff <= 1` по каналу.

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
#### Review
