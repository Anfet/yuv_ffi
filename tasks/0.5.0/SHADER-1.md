# SHADER 1 — Раскладка плоскостей YUV в одну текстуру
**Status:** ACCEPTED · **Tier:** T2 · **Owner:** — · **Depends On:** — · **Probe:** windows

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
   Chroma с `pixelStride 2` копируется строкой целиком, одним `setRange` из `row · rowStride`: у I420 — `2·cw − 1`
   байт, у NV12 — `2·cw`. У I420 байты на нечётных позициях (у Android-камеры это V) попадают в текстуру и не
   читаются; ради этого шаг 2 и сохранён. Побайтный цикл — нет.
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
- В `YuvPlanesTexture.pack` I420 chroma с `pixelStride 2` теперь копируется одним `setRange` на строку длиной
  `2·cw−1`; interleaved байты сохраняются, row padding не попадает в текстуру. `_max` заменён на `dart:math`,
  недостижимая ветка исключения удалена.
- `flutter test test/yuv_planes_texture_test.dart` — 14 passed: все исходные пиксели через адресацию шейдера для трёх
  раскладок, четырёх размеров, padding, независимого буфера, отказов и непрерывных Android I420 chroma-строк.
- `pwsh -File tool/ci/vm.ps1` — 601/601 passed; `pwsh -File tool/ci/example.ps1` при `FLUTTER_VERSION=3.44.9` —
  analyze и Web build passed. `flutter test --tags probe` — 20 passed, 1 expected timing skip,
  `PROBE scope: ops=all formats=all cases=1188/1188`.
#### Review
```text
Pool: STAGE4-VIEW; SHADER 1
Outcome: REWORK
Reviewed-Head: 6ab07ad
Merged-Head: none
Fixed: none
Blocking: I420 с chroma pixelStride 2 копируется побайтно (_copyStridedChroma) — по решению 2 строка копируется
  одним setRange длиной 2·cw − 1; это основной путь Android-камеры, 1920x1080 — около миллиона операций Dart на кадр.
Advisory: случай «последняя строка chroma длиной 2·cw − 1» (форма Android-буфера), если YuvPlane его принимает;
  _max — заменить на dart:math; ветку throw StateError('Validated above.') убрать.
```
Раскладка и адресация по решениям 2–3 верны, тест читает каждый пиксель.

Повторное ревью 02.10.2026:
```text
Pool: STAGE4-VIEW; SHADER 1
Outcome: ACCEPTED
Reviewed-Head: 0b3eddd
Merged-Head: none (слияние — вместе с пулом)
Fixed: none
Blocking: none
Advisory: тест Android-строк берёт полные строки chroma; укороченная последняя строка (`2·cw − 1` байт) не
  проверена — setRange читает ровно столько, риска нет.
```
Проверено: chroma `pixelStride 2` у I420 копируется одним `setRange` длиной `2·cw − 1`, NV12 — `2·cw`; `_max` и
недостижимая ветка убраны; тест побайтно сравнивает строки текстуры с исходными. Перепрогон Reviewer — в Review GEOM 1
(общий прогон, 26 passed).
