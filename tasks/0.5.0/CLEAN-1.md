# CLEAN 1 — Убрать следы замеров из example
**Status:** REVIEW · **Tier:** T3 · **Owner:** Luna · **Depends On:** — · **Probe:** none

#### Goal
Убрать экран `Pack00BenchScreen` и кнопку PACK-00, хуки VIEW-03 (`debugYuvCameraPreviewMobileEvent`, часы, enum), переключатель `kYuvCameraPreviewPackPlanes` (остаётся плотный импорт); `kYuvCameraPreviewFlipAndroid` заменить параметром ориентации.

#### Architect Decision
Убрать только временные измерительные элементы example. Обычное превью продолжает
импортировать плоскости в плотную раскладку. Ориентацию Android-превью передавать
явным параметром от места создания превью до преобразования кадра; текущее
значение в существующем вызове должно давать тот же результат, что и прежний
`kYuvCameraPreviewFlipAndroid`. Это локальный контракт example, без нового API
пакета и без зависимости от будущего `FrameGeometry` (GEOM 1).

#### Scope

- Удалить `Pack00BenchScreen`, кнопку/маршрут PACK-00 и тесты, проверяющие
  исключительно этот стенд.
- Удалить VIEW-03-событие `debugYuvCameraPreviewMobileEvent`, измерительные
  часы, enum и связанную с ними передачу/отображение диагностических данных.
- Удалить `kYuvCameraPreviewPackPlanes` и ветку импорта без упаковки: оставить
  плотный импорт как единственный путь обычного превью.
- Заменить чтение `kYuvCameraPreviewFlipAndroid` явной передачей ориентации в
  пределах example и скорректировать относящиеся к этому вызовы и проверки.

#### Constraints

- Не менять `lib/`, native `src/`, публичный API, алгоритм упаковки или
  поведение импорта видимых пикселей. Тесты упаковки кадров, не привязанные к
  удаляемому стенду, сохранить.
- Не переносить и не переписывать камерный поток: это CAMERA 1/2. Не вводить
  `FrameGeometry`: это GEOM 1.
- Не оставлять глобальный переключатель ориентации под другим именем. Если
  текущий параметр платформы уже описывает нужную ориентацию, использовать его;
  иначе ввести минимальный тип внутри example, представляющий именно текущие
  преобразования кадра.

#### Definition of Done

- В example больше нет экрана/кнопки PACK-00, измерительных хуков VIEW-03 и
  обоих `kYuvCameraPreview*`-переключателей; обычное превью создаёт плотные
  плоскости одним путём.
- Ориентация задаётся вызывающей стороной, Android-превью при текущем вызове
  визуально эквивалентно прежнему; другие платформы сохраняют прежнюю
  ориентацию и работу превью.
- Не осталось импортов, тестов и документации example, ссылающихся на
  удалённый стенд или измерительные хуки.

#### Validation

- `Probe: none`: меняется только example; изменений `lib/src/yuv/impl/**`,
  `src/**` и заявления об ускорении нет.
- Из корня пакета: `pwsh -File tool/ci/example.ps1` (ключ `example` по
  `AGENTS.md`). Проверить целевые тесты затронутых компонентов example и
  отсутствие ссылок на перечисленные удалённые имена.
- В Executor Report записать команды, результат и способ проверки
  эквивалентности ориентации Android и остальных платформ.

#### Executor Report

- Удалены экран и тест PACK-00, кнопка и маршрут; из мобильного превью удалены VIEW-03 hook, enum и часы.
- Плотная упаковка стала единственным путём импорта; сохранены тесты видимых пикселей, padding и pixel stride.
- Android flip передаётся параметром от `CameraScreen` до обработки кадра; значение `true` совпадает с прежним глобальным значением. Flip применяется только в Android ветке, остальные платформенные пути не менялись.
- Проверка ссылок в `example/` на удалённые имена: совпадений нет.
- `flutter test test/camera_image_pack_planes_test.dart test/camera_image_to_yuv_image_padding_test.dart test/camera_preview_lifecycle_test.dart test/desktop_camera_preview_test.dart` (из `example/`) — passed.
- `$env:FLUTTER_VERSION='3.44.9'; pwsh -File tool/ci/example.ps1` — остановился на `flutter analyze`: два info в нетронутых `integration_test/helpers/probe/layout_pack_test.dart` и `probe_selection_test.dart` (`library_annotations`). `pub get` прошёл.
- Добавлена library directive после `@Tags(['probe'])` в двух probe integration-тестах; `flutter analyze` проходит без warnings.
- `$env:FLUTTER_VERSION='3.44.9'; pwsh -File tool/ci/example.ps1` — passed, exit code 0 (`pub get`, `analyze`, `build web`).
- `flutter test test/camera_image_pack_planes_test.dart test/camera_image_to_yuv_image_padding_test.dart test/camera_preview_lifecycle_test.dart test/desktop_camera_preview_test.dart` (из `example/`) — passed, 47 tests.

#### Review

**Reviewed-Head:** `d3867c73a1d47874f367df10cbf8246a103d7aa9`

**Status:** TODO

**Blocking:**

- Обязательная валидация не проходит: `$env:FLUTTER_VERSION='3.44.9'; pwsh -File tool/ci/example.ps1` повторно завершается с exit code 1 на `flutter analyze`. Причина — два `library_annotations` info в `example/integration_test/helpers/probe/layout_pack_test.dart:1` и `probe_selection_test.dart:1`. Карточка требует успешный `tool/ci/example.ps1`; без этого DoD не доказан.

**Evidence:**

- Выборочная проверка `flutter test test/camera_image_pack_planes_test.dart test/camera_image_to_yuv_image_padding_test.dart` из `example/` — 10 passed.
- Статический поиск не нашёл удалённые PACK-00/VIEW-03 имена; вызов `CameraScreen` передаёт `flipAndroidCameraHorizontally: true`, что соответствует прежнему значению. Параметр применяется только в Android-ветке.
