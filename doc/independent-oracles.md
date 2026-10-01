# Независимые оракулы для проверки пикселей

Выжимка исследования YUV-39 (14.09.2026, эпоха 0.2.5). Полный документ описывает старые C-функции, которых после
ABI v1 нет; он в git: `git show 85dda67:native-primitives-research.md`. Здесь — только то, что пригодно для
«Тестов 6» (чистка дублей) и любой проверки «наш результат против чужой реализации».

## Кандидаты

| Библиотека | Роль | Лицензия | Закреплённый коммит (14.09.2026) |
| --- | --- | --- | --- |
| **libyuv** | основной независимый оракул; возможный кандидат на линковку | BSD-3 | `2dd4257364d39c38d79465c4ddc4b93137fe729b`, `LIBYUV_VERSION` 1971 |
| FFmpeg libswscale | только сверка чисел, не линковка (LGPL) | LGPL | `639ee849526cfe61ceb312776335c245b98bd9d4` |
| OpenCV imgproc | только семантика границ blur, не зависимость | Apache-2.0 | `da8527c1894eb7820055116c415ca1f0a648b173` (ветка `4.x`) |

## Как собрать libyuv-оракул

Скалярные C-пути, SIMD отключён, чтобы результат не зависел от CPU:

```
clang++ -std=c++17 -O0 -g0 -w -I <libyuv>/include \
  -DLIBYUV_DISABLE_X86 -DLIBYUV_DISABLE_SME -DLIBYUV_DISABLE_NEON -DLIBYUV_DISABLE_SVE \
  harness.cc \
  <libyuv>/source/{convert,convert_from_argb,row_common,planar_functions,cpu_id,scale,scale_common,rotate,rotate_common,row_any,scale_any,rotate_any,convert_argb,convert_from,scale_argb,scale_uv,scale_rgb,video_common}.cc \
  -o harness
```

## Соответствие нашим операциям

| Наше | libyuv | Оговорки |
| --- | --- | --- |
| I420 / NV12 → BGRA | `I420ToARGBMatrix` / `NV12ToARGBMatrix` с `kYuvI601Constants` | матрицу передавать явно |
| BGRA → I420 / NV12 | `ARGBToI420` (BT.601 limited, `kArgbI601Constants`) / `ARGBToNV12` | `ARGBToJ420` — это full range (JPEG), нам не подходит |
| I420 ↔ NV12 | `I420ToNV12` / `NV12ToI420` | |
| поворот | `I420Rotate`, `NV12ToI420Rotate`, `ARGBRotate` | не in-place |
| горизонтальное зеркало | `I420Mirror`, `NV12Mirror`, `ARGBMirror` | отдельный вертикальный примитив в исследовании не найден |
| crop | нет API | смещение указателя + `CopyPlane` |
| grayscale / black-white / negate / box, mean, gaussian blur | прямых аналогов нет | blur — только семантика границ из OpenCV |

## Что учитывать при сравнении

- **libyuv `ARGB` в памяти — это B, G, R, A**, то есть ровно наш `BGRA8888`: буфер передаётся без перестановки.
- **libyuv понимает только row stride, не pixel stride.** Кадры с зазором между сэмплами (I420 с `pixelStride = 2`)
  сначала упаковывать.
- **Размеры chroma** — с округлением вверх: `(W + 1) / 2`, `(H + 1) / 2`.
- **Допуск:** по Y — не больше 1 уровня (у libyuv смещение округления стоит в другом месте). По U/V расхождение
  может быть большим из-за другого алгоритма субдискретизации 2×2; его нужно объяснять, а не списывать на округление.
- Исторически это исследование нашло, что BGRA → YUV у нас считался в full range, а YUV → BGRA — в limited. В ABI v1
  это исправлено: в `src/` одна limited-формула BT.601.

## Сверка эталона

`bash tool/oracle/check_reference.sh` на Mac скачивает libyuv в свой временный каталог, закрепляет
`2dd4257364d39c38d79465c4ddc4b93137fe729b`, собирает скалярный harness и сверяет `test_pattern_512`.
Ожидаемые PNG системный `sips` декодирует в тот же временный каталог; ни libyuv, ни преобразованные файлы не
становятся частью пакета. Скрипт печатает максимум и долю отличий для Y, U/V и BGRA, а при нарушении допуска —
пару, канал, координаты и ожидаемое/фактическое значение.

`source_nv21_uv.yuv` хранит U,V в соответствии с legacy-контрактом пакета. libyuv `NV21` хранит V,U, поэтому harness
сравнивает U и V семантически, а `NV21ToARGBMatrix` получает исходный libyuv-буфер без перестановки.

Для негативного контроля скрипт создаёт испорченную копию `source_i420.yuv` только во временном каталоге:

```bash
ORACLE_CORRUPT_I420=1 bash tool/oracle/check_reference.sh
```
