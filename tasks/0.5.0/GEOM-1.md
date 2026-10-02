# GEOM 1 — Геометрия кадра `YuvFrameGeometry`
**Status:** REVIEW · **Tier:** T2 · **Owner:** Reviewer · **Depends On:** CLEAN 2 · **Probe:** windows

#### Goal
`YuvFrameGeometry` в `lib/`: размер кадра, ориентация (поворот + зеркало), `contain`/`cover`, `alignment`;
`copyWith`. `zoom`/`focus`/`crop` из плана перенесены (D-19). Даёт матрицы для шейдера и Canvas; правило для ML Kit (поворот — ему, зеркало —
после). `apply(YuvImage)` вырезает видимую часть кадра существующими операциями, без native. Исправляет в
`example/lib/widgets/face_rect_paint.dart` формулу для 90°/270° и жёсткий `cover`.

Пул этапа 4 «показ кадров»: GEOM 1 → SHADER 1 → SHADER 2 → SHADER 3 → PRESENT 1.

#### Architect Decision
1. **Три пространства координат** (dartdoc класса начинается с них):
   - **source** — пиксели кадра как он пришёл, `W×H`;
   - **upright** — source после поворота, без зеркала, `Uw×Uh`. В нём ML Kit возвращает рамки, если получил сырой
     кадр и поворот в метаданных;
   - **view** — логические пиксели виджета, `Vw×Vh`.
2. **`YuvFrameOrientation`** — `rotation` (`YuvImageRotation`, по часовой, делает кадр прямым) и `mirrored`
   (горизонтальное зеркало **после** поворота — как нынешнее Android-превью). `const` конструктор,
   `static const upright`, `==`/`hashCode`, `YuvImage applyTo(YuvImage source)` — новое изображение:
   `source.rotated(rotation)`, затем `applyFlipHorizontal()`, если `mirrored`.
3. **`YuvFrameFit`** — `enum { contain, cover }`.
4. **`YuvFrameGeometry`** — неизменяемый класс:
   ```dart
   YuvFrameGeometry({
     required Size sourceSize,
     required Size viewSize,
     YuvFrameOrientation orientation = YuvFrameOrientation.upright,
     YuvFrameFit fit = YuvFrameFit.contain,
     Alignment alignment = Alignment.center,
   })
   ```
   Члены: `Rect destinationRect` (куда ложится контент во view), `Matrix4 sourceToView`, `Matrix4 viewToSource`,
   `Matrix4 uprightToView`, `Rect visibleSourceRect`, `YuvImage apply(YuvImage source)`, `copyWith`, `==`/`hashCode`.
   Точки и прямоугольники отображаются готовыми `MatrixUtils.transformPoint`/`transformRect` — своих map-методов нет.
   Неположительные размеры → `ArgumentError`.
5. **Формулы** — нормативные. Координаты непрерывные: пиксель `(i, j)` занимает `[i, i+1) × [j, j+1)`.
   1. **source → upright:** `r0: (x, y)`; `r90: (H − y, x)`; `r180: (W − x, H − y)`; `r270: (y, W − x)`.
      Это то же отображение пикселей, что у `rotated()` (`doc/api-abi-0.4-design.md`, transforms).
   2. **Зеркало:** `(u, v) → (Uw − u, v)`, если `mirrored`.
   3. **Масштаб:** `s = (contain ? min : max)(Vw / Uw, Vh / Uh)`; `Sw = Uw · s`, `Sh = Uh · s`.
   4. **Сдвиг** (как `Alignment.inscribe`): `tx = (Vw − Sw) · (alignment.x + 1) / 2`,
      `ty = (Vh − Sh) · (alignment.y + 1) / 2`.
   5. **В view:** `view = d · s + (tx, ty)`; `destinationRect = Rect.fromLTWH(tx, ty, Sw, Sh)`.
   6. `sourceToView` = 1 → 2 → 5, `uprightToView` = 2 → 5, `viewToSource` = обратная к `sourceToView`.
   7. `visibleSourceRect` = `transformRect(viewToSource, destinationRect ∩ (0, 0, Vw, Vh))`.
6. **`apply(source)`** = `orientation.applyTo(source.cropped(visibleSourceRect))`. Округление и нечётное начало делает
   сам `cropped()` (публичный crop их поддерживает, Q2 в `doc/api-abi-0.4-design.md`). Источник не меняется.
7. **ML Kit** (dartdoc `uprightToView`, `example/README.md`): ML Kit получает сырой кадр и `orientation.rotation`;
   рамки переводит на экран `MatrixUtils.transformRect(geometry.uprightToView, box)`.
8. **Файлы:** `lib/src/geometry/yuv_frame_geometry.dart` (все три типа), экспорт строкой в `lib/yuv_ffi.dart`.
9. **Пример:** `FaceRectPainter` получает `YuvFrameGeometry` и рисует `transformRect(uprightToView, rect)`; функция
   `mapImageRectToWidget` удаляется. `_ImageWidget` в `main.dart` строит геометрию из размера картинки и холста.

#### Scope
- `lib/src/geometry/yuv_frame_geometry.dart`, `lib/yuv_ffi.dart`.
- `test/yuv_frame_geometry_test.dart`.
- `example/lib/widgets/face_rect_paint.dart`, `example/lib/main.dart`.
- `README.md` (короткий раздел: три пространства, правило ML Kit), `CHANGELOG.md` (`0.5.0-dev.1`),
  `test/public_surface_test.dart`.

#### Constraints
- Native, `lib/src/yuv/impl/**` и интерфейс `YuvImage` не трогать.
- `zoom`, `focus`, `crop` не добавлять (D-19): зум — `CameraController.setZoomLevel()`, часть кадра на экране —
  `cover` + `alignment`, вырезать данные — `cropped()`/`applyCrop()`.

#### Definition of Done
- [ ] API и формулы — по решениям 1–7.
- [ ] Тесты: для 8 ориентаций углы source-кадра попадают туда, куда ведут формулы 1–6; `contain` и `cover` при view
      шире и выше кадра, `alignment` по углам; отказы из решения 4.
- [ ] Тест «`apply()` = нарисованное»: кадр рисуется через `canvas.transform(sourceToView.storage)` + `drawImage`
      (`FilterQuality.none`) в масштабе 1:1 со сдвигом; видимая часть побайтно равна
      `apply(frame).toBgraBytes()`. 8 ориентаций; I420 и BGRA; нечётный размер.
- [ ] `FaceRectPainter` на геометрии; `example/test` проходит.

#### Validation
Ключи: `lib/*` → `vm example`, `test/*` → `vm`, `example/*` → `example`.

- `dart format --line-length 150`; `flutter analyze` в корне и в `example/`.
- `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/example.ps1`.
- Probe `windows`: `flutter test --tags probe` — вердикты в отчёт.

#### Executor Report
- Реализованы `YuvFrameGeometry`, `YuvFrameOrientation` и `YuvFrameFit`; API экспортирован. `FaceRectPainter` и
  `_ImageWidget` используют `uprightToView` из одной геометрии; README описывает контракт ML Kit.
- `test/yuv_frame_geometry_test.dart`: 12 passed. Проверены восемь поворотов/зеркал, `contain`/`cover`, выравнивание,
  отказы, независимость `apply()` и Canvas-пиксели для I420/BGRA.
- `flutter analyze` — без warnings/errors (56 существующих info `library_annotations`); `flutter analyze` в `example/`
  — passed; `pwsh -File tool/ci/vm.ps1` — 585/585 passed; `pwsh -File tool/ci/example.ps1` при
  `FLUTTER_VERSION=3.44.9` — passed; `flutter test --tags probe` — 20 passed, 1 expected timing skip,
  `PROBE scope: ops=all formats=all cases=1188/1188`.
#### Review
