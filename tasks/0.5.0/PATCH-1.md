# PATCH 1 — Вставка фрагмента в изображение
**Status:** REVIEW · **Tier:** T2 · **Owner:** Engineer · **Depends On:** — · **Probe:** windows

#### Goal
Было PATCH-00 (план 0.4.3; файл удалён, история — в git). Непрозрачная вставка одного `YuvImage` в область другого:
`cropped(region) → rotated(rotation) → applyPatch(fragment, x: ..., y: ...)`. Источник вставляется целиком в
целочисленные координаты назначения без масштабирования и смешивания. Одинаковые форматы; выход за границы
отклоняется, а не обрезается. tight, padded и pixel-gapped layout. Ошибка оставляет содержимое и revision без
изменений; успешная вставка повышает revision ровно один раз. Стоимость небольшой вставки замеряется на устройстве
до решения о native-реализации. `srcIn/srcOut`, альфа, масштабирование и попиксельное рисование — не в задаче.

Отдельный пул этапа 4: с пулом «показ кадров» не пересекается, кроме строки экспорта в `lib/yuv_ffi.dart` и записи
в `CHANGELOG.md`.

#### Architect Decision
1. **Зависимость от GEOM 1 снята.** Общего правила 2×2 с геометрией нет: `YuvFrameGeometry.apply` режет кадр точно по
   видимой области, а публичный crop поддерживает нечётное начало (`doc/api-abi-0.4-design.md`, Q2). Правило
   выравнивания ниже принадлежит только вставке.
2. **API — расширение, не метод интерфейса:**
   ```dart
   extension YuvImagePatch on YuvImage {
     YuvImage applyPatch(YuvImage fragment, {required int x, required int y});
   }
   ```
   `lib/src/yuv/shared/yuv_patch.dart`, экспорт `show YuvImagePatch` строкой в `lib/yuv_ffi.dart` — как
   `YuvImagePack`. Добавление метода в `abstract interface class YuvImage` сломало бы внешние `implements YuvImage`;
   расширение работает с любым `YuvImage` через `planes` и `markDirty()`.
3. **Реализация — чистый Dart над плоскостями назначения**, без native (D-17) и без копии всего кадра: запись прямо
   в `planes[i].bytes` назначения, затем `YuvRevision.bump(this)` один раз. Строка — `setRange`, когда у обеих сторон
   `pixelStride == sampleBytes`; иначе посэмпльно. Пишутся только видимые сэмплы; row padding и байты pixel gap
   назначения не трогаются. На Web тот же код: плоскости обоих backend-ов — память Dart (`YuvImageState`).
4. **Проверки до первой записи** (все — `ArgumentError`, сообщение называет правило):
   - `fragment.format == format`;
   - `identical(fragment, this)` запрещено;
   - `x >= 0`, `y >= 0`, `x + fragment.width <= width`, `y + fragment.height <= height`;
   - I420/NV12 — **правило chroma 2×2**: `x` и `y` чётные; `fragment.width` чётная или `x + fragment.width == width`;
     `fragment.height` чётная или `y + fragment.height == height`. Тогда каждый chroma-сэмпл назначения в области
     вставки покрыт только пикселями фрагмента, и chroma копируется блоками `[x/2, x/2 + ceil(w/2))` ×
     `[y/2, y/2 + ceil(h/2))` из `[0, ceil(w/2)) × [0, ceil(h/2))` фрагмента без пересчёта. Нечётная ширина у правого края
     назначения ложится на его неполный последний chroma-столбец — за плоскость не выходит.
   - BGRA — без выравнивания.
   После проверок запись не может бросить, поэтому частичного состояния нет.
5. **Revision:** успех — ровно +1 (и для внешнего `implements YuvImage` через `Expando`); отказ — без изменений.
   Источник (`fragment`) не меняется.
6. **Замер до решения о native.** Pixel 3, release: вставка 64×64 и 256×256 в 1920×1080, I420/NV12/BGRA, tight и
   padded, медиана из 30 после 5 прогревов, подготовка вне таймера. Временная точка входа в `example/` не
   коммитится; вывод — в `doc/perf-findings.md`. Если 256×256 в tight I420 дольше 2 мс, Executor пишет в отчёт
   рекомендацию о native-карточке; сама native-реализация не входит в задачу.

#### Scope
- Создать `lib/src/yuv/shared/yuv_patch.dart`; экспорт в `lib/yuv_ffi.dart`.
- `test/yuv_image_patch_test.dart` (тег `contract`).
- `README.md` — раздел о вставке с правилом 2×2 и примером `cropped → rotated → applyPatch`;
  `CHANGELOG.md` — `0.5.0-dev.1`; `doc/perf-findings.md` — вывод замера; `test/public_surface_test.dart`.

#### Constraints
- Native и `lib/src/yuv/impl/**` не трогать. Интерфейс `YuvImage` не менять.
- Ветка пула от `dev`; при параллельном пуле «показ кадров» конфликт возможен только в `lib/yuv_ffi.dart` и
  `CHANGELOG.md` — интеграцию после слияния соседнего пула делает Executor, не Reviewer.

#### Definition of Done
- [x] API и правила — по решениям 2–5.
- [x] Тесты: для I420, NV12 и BGRA — вставка в (0,0), во внутреннюю чётную позицию и к правому нижнему краю
      нечётного кадра; один случай с padded и один с gap layout (у назначения и у фрагмента); фрагмент после
      `rotated(rotation90)`. Ожидание — посэмпльный оракул в тесте: вставленная
      область равна фрагменту, остальные видимые сэмплы и все байты padding/gap назначения не изменились.
- [x] Отказы: другой формат, `identical`, выход за любую границу, отрицательные координаты, нечётные `x`/`y` (YUV),
      нечётная ширина/высота не у края (YUV) → `ArgumentError`; байты и revision назначения не изменились.
- [x] Revision +1 на успех; внешний `implements YuvImage` (тестовый fake) получает вставку и +1 через `revision`.
- [x] Замер решения 6 — в отчёте и `doc/perf-findings.md`, с рекомендацией по native.
- [x] README/CHANGELOG/public surface обновлены.

#### Validation
Ключи: `lib/*` → `vm example`, `test/*` → `vm`. Ветка пула — `vm+example/STAGE4-PATCH`.

- `dart format --line-length 150`; `flutter analyze`.
- `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/example.ps1`.
- `flutter test test/yuv_image_patch_test.dart` — число тестов в отчёт.
- Probe `windows`: `flutter test --tags probe` — вердикты в отчёт.
- Pixel 3 release — замер решения 6.

#### Executor Report
- Добавлено публичное расширение `YuvImagePatch`: все проверки выполняются до записи, tight rows копируются через `setRange`, gapped samples — посэмпльно; revision назначения повышается один раз.
- Контрактный файл: 10 тестов; вместе с public-surface — 14/14 PASS. Покрыты I420/NV12/BGRA, origin/interior/odd edge, padded/gapped layout, rotated fragment, все отказы и foreign `implements YuvImage`.
- Pixel 3 release, медиана 30 после 5 прогревов, мкс (`64×64 / 256×256`): I420 tight `3 / 20`, padded `3 / 21`; NV12 tight `2 / 17`, padded `2 / 16`; BGRA tight `2 / 27`, padded `2 / 28`.
- Tight I420 256×256 = 0,020 мс, значительно ниже порога 2 мс. Native-реализация не рекомендуется.
- Validation: `flutter analyze` — без новых warning/error (58 существующих info); `flutter test --tags probe` — 20 PASS, 1 ожидаемый skip, `1188/1188`; `tool/ci/vm.ps1` — 616/616; `tool/ci/example.ps1` — PASS на Flutter 3.44.9.

#### Review
