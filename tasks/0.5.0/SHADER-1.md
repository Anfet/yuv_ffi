# SHADER 1 — Раскладка плоскостей YUV в одну текстуру
**Status:** REVIEW · **Tier:** T2 · **Owner:** Reviewer · **Depends On:** — · **Probe:** windows

#### Goal
Первая из трёх карточек шейдерного пути (SHADER 1 — раскладка, SHADER 2 — шейдер и рендерер, SHADER 3 — проба на
платформах). Здесь — чистая Dart-функция без GPU: из I420/NV12 `YuvImage` собрать байты одной RGBA8888-текстуры и
числа, по которым шейдер найдёт Y, U и V пикселя.

Пул этапа 4 «показ кадров»: GEOM 1 → SHADER 1 → SHADER 2 → SHADER 3 → PRESENT 1.

#### Architect Decision
1. **Внутренний тип** `lib/src/widgets/yuv_planes_texture.dart` (не экспортируется):
   ```dart
   final class YuvPlanesTexture {
     /// Returns null when the frame has no shader layout; the caller then draws it as BGRA.
     static YuvPlanesTexture? pack(YuvImage frame);
     final Uint8List bytes;                 // width * 4 * height
     final int width, height;               // texture size in texels / rows
     final ({int row, int offset, int step}) u, v;
   }
   ```
   `pack` копирует всё сразу; после возврата `frame` можно менять.
2. **Раскладка.** `W×H` — кадр, `cw = ceil(W/2)`, `ch = ceil(H/2)`. 4 байта плоскостей на тексель. Y — строки
   `[0, H)`, байт `x`. Строки копируются `setRange`, row padding не копируется.
   | Источник | U | V | байт в строке, max | строк |
   | --- | --- | --- | --- | --- |
   | I420, chroma `pixelStride 1` | строки `[H, H+ch)`, байт `cx` | те же строки, байт `cw + cx` | `max(W, 2·cw)` | `H + ch` |
   | I420, chroma `pixelStride 2` (Android-камера) | строки `[H, H+ch)`, байт `2·cx` | строки `[H+ch, H+2ch)`, байт `2·cx` | `max(W, 2·cw − 1)` | `H + 2·ch` |
   | NV12, chroma `pixelStride 2` | строки `[H, H+ch)`, байт `2·cx` | те же строки, байт `2·cx + 1` | `max(W, 2·cw)` | `H + ch` |
   Ширина текстуры = `ceil(max / 4)`. Всё остальное (BGRA, pixel gap Y, другой pixel gap chroma, сторона текстуры
   больше 4096) → `null`.
3. **Адресация** (её же делает шейдер): байт `b` строки `r` — тексель `(floor(b/4), r)`, канал `b mod 4`. Y пикселя
   `(x, y)` — строка `y`, байт `x`; U — строка `u.row + floor(y/2)`, байт `u.offset + floor(x/2) · u.step`; V — так же.

#### Scope
- `lib/src/widgets/yuv_planes_texture.dart`; `test/yuv_planes_texture_test.dart` (тег `contract`).

#### Constraints
- Без GPU и `dart:ui`. Native и `lib/src/yuv/impl/**` не трогать.

#### Definition of Done
- [ ] Тест читает каждый пиксель по адресации решения 3 и сравнивает Y, U, V с исходными плоскостями: три раскладки ×
      размеры `1x1`, `3x5`, `33x17`, `720x480` × с row padding и без.
- [ ] `null` для BGRA и для кадра со стороной текстуры больше 4096; мутация `frame` после `pack` не меняет `bytes`.

#### Validation
Ключи: `lib/*` → `vm example`, `test/*` → `vm`.

- `dart format --line-length 150`; `flutter analyze`; `pwsh -File tool/ci/vm.ps1`.
- Probe `windows`: `flutter test --tags probe`.

#### Executor Report
- Добавлен внутренний `YuvPlanesTexture.pack`: I420 с chroma stride 1/2 и NV12 раскладываются в RGBA-текстуру без
  row padding; неподдерживаемая геометрия возвращает `null` для BGRA fallback.
- `flutter test test/yuv_planes_texture_test.dart` — 13 passed: все исходные пиксели через адресацию шейдера для трёх
  раскладок, четырёх размеров, padding, независимого буфера и отказов.
- `pwsh -File tool/ci/vm.ps1` — 598/598 passed. `flutter test --tags probe` — 20 passed, 1 expected timing skip,
  `PROBE scope: ops=all formats=all cases=1188/1188`. Example CI без изменения его путей сохраняет результат GEOM 1.
#### Review
