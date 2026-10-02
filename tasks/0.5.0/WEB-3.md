# WEB 3 — Убрать `dart:html`: `package:web` в загрузчике и Web-источнике камеры
**Status:** ACCEPTED · **Tier:** T2 · **Owner:** — · **Depends On:** CAMERA 1 · **Probe:** windows

#### Goal
`dart:html` устарел: его заменили `package:web` и `dart:js_interop`, и код с ним не компилируется в WebAssembly
(`flutter build web --wasm`). Сейчас он остался в двух местах: в загрузчике WASM самого пакета и в Web-источнике
камеры example. Перевести оба на `package:web` и добавить проверку, что Web-камера реально отдаёт кадры — без неё
CAMERA 1 уже один раз сломала Web незаметно.

Пул этапа 4 «камера»: CAMERA 1 → CAMERA 2 → WEB 3.

#### Architect Decision
1. **Загрузчик пакета** `lib/src/loader/impl/wasm_loader_web.dart`: пять обращений к `html.document`
   (`querySelector`, `ScriptElement`, `head.append`, `remove`) — на `package:web` (`web.document`,
   `web.HTMLScriptElement`). Зависимость `web: ^1.1.1` — в `dependencies` корневого `pubspec.yaml` (сейчас она
   транзитивная, 1.1.1). Поведение и публичное API не меняются.
2. **Web-источник камеры** `example/lib/camera/impl/yuv_camera_frame_source_web.dart`: `VideoElement`,
   `CanvasElement`, `MediaStream`, `getUserMedia`, `requestAnimationFrame` — на `package:web`; `MediaStreamTrackProcessor`
   и `VideoFrame` тоже есть в `package:web` 1.1.1 (`mediacapture_transform.dart`, `webcodecs.dart`) — через них, а не
   через `js_util_compat_web.dart`. Если после перевода shim никем не используется — удалить. `web` — в
   `dependencies` `example/pubspec.yaml`. Логика источника (поколения, остановка, fallback на canvas) не меняется.
3. **Подавления уходят.** `// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use` удалить;
   `flutter analyze` в корне и в `example/` чист без них. Попутно: `catch (_)` в источнике (отказ
   `MediaStreamTrackProcessor` → canvas, отказ `copyTo` BGRA → RGBA) получают комментарий, почему ошибка не
   логируется (правило CODESTYLE, раздел 9).
4. **Проба Web-камеры** — `example/integration_test/camera_source_web_smoke_test.dart` (имя без суффикса
   `_web_test`, чтобы матрица `Assert-WebSourceMatrix` его не требовала): `availableCameras()` → `CameraController`
   → `YuvCameraFrameSource.start()`; за 10 с приходит хотя бы один кадр с `width > 0`, `height > 0`, и его
   `image.toBgraBytes()` не все нули; затем `dispose()` — кадры больше не приходят. Запуск — отдельный блок
   `Start-WebDriver` в `tool/ci/web.ps1` с фейковой камерой Chrome:
   `-Arguments @('--web-browser-flag=--use-fake-device-for-media-stream', '--web-browser-flag=--use-fake-ui-for-media-stream')`.
   Итоговую строку `Web CI passed` дополнить `camera smoke=1`.
5. **Запасной путь при сбое пробы**:
   `flutter drive` скрывает `--web-browser-flag` в `--help`, но передаёт его в `goog:chromeOptions.args`
   (`packages/flutter_tools/lib/src/drive/web_driver_service.dart` в SDK 3.44).
   - **A. Фейковая камера не появляется** (`getUserMedia` падает с `NotAllowedError`/`NotFoundError`,
     `availableCameras()` пуст) — проба остаётся ручной командой в `example/README.md`, блок в `web.ps1` не
     добавляется; вывод `navigator.mediaDevices.enumerateDevices()` из пробы, запуск без `--headless` и его результат
     на Windows — в отчёт. Если и вручную кадров нет — `ARCHITECT_REQUIRED`.

#### Scope
- `lib/src/loader/impl/wasm_loader_web.dart`, `pubspec.yaml`.
- `example/lib/camera/impl/yuv_camera_frame_source_web.dart`, `example/lib/camera/impl/js_util_compat_web.dart`
  (удаление, если не нужен), `example/pubspec.yaml`.
- `example/integration_test/camera_source_web_smoke_test.dart`, `tool/ci/web.ps1` (один блок запуска и итоговая строка).
- `CHANGELOG.md` (`0.5.0-dev.1`: загрузчик на `package:web`).

#### Constraints
- Сборку `flutter build web --wasm` в задачу не включать: она упирается в WASM-backend пакета — отдельный вопрос.
- `lib/src/yuv/impl/**`, native и `lib/src/web/impl/js_util_compat_web.dart` пакета не трогать (он уже на
  `dart:js_interop`).
- Матрицу `Assert-WebSourceMatrix` (13 источников, 62 случая) не менять.

#### Definition of Done
- [x] `dart:html` не встречается в `lib/` и `example/lib/` (поиск — в отчёт); подавления из решения 3 нет;
      `flutter analyze` в `example/` чист, а корневой завершается успешно с 58 существующими `library_annotations` info в `test/`.
- [x] `tool/ci/web.ps1` проходит целиком, включая пробу Web-камеры.
- [x] Поведение загрузчика не изменилось: `wasm_loader_lifecycle_web_test` и `wasm_bootstrap_web_test` проходят без
      правок.

#### Validation
Ключи: `pubspec.yaml`, `example/integration_test/*` → `all`; `tool/ci/web.ps1` → `web`. Ветка пула —
`all/STAGE4-CAMERA`.

- `dart format --line-length 150`; `flutter analyze` в корне и в `example/`.
- `pwsh -File tool/ci/web.ps1`, `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/example.ps1`,
  `pwsh -File tool/ci/windows.ps1`.
- Probe `windows`: в составе `tool/ci/windows.ps1`.

#### Executor Report

**Result:** REVIEW. Коммиты реализации: `3b63e9b`, `52d724e`, `8e5d065`, `6991cdb`.

- `dart:html` в `lib/` и `example/lib/`: 0 совпадений. Локальный `js_util_compat_web.dart` источника камеры удалён;
  `MediaStreamTrackProcessor`, reader и `VideoFrame` используют типы `package:web`.
- `flutter analyze` в корне завершился с code 0; 58 info `library_annotations` находятся только в существующих файлах `test/`.
  `flutter analyze` в `example/`: `No issues found`.
- `pwsh -File tool/ci/web.ps1`: PASS — Chrome `154.0.8037.98`, sources=13, integration cases=62, reference matrix=119,
  camera smoke=1. Проба получает непустой кадр с fake device и проверяет отсутствие новых кадров после `dispose()`.
- `pwsh -File tool/ci/vm.ps1`: PASS, 616/616.
- `FLUTTER_VERSION=3.44.9 pwsh -File tool/ci/example.ps1`: PASS, включая `flutter build web`.
- `pwsh -File tool/ci/windows.ps1`: PASS; Windows probe прошла в составе скрипта.

#### Review

Ревью 02.10.2026:
```text
Pool: STAGE4-CAMERA; WEB 3
Outcome: ACCEPTED
Reviewed-Head: 2ddf677 + правки Reviewer (не закоммичены)
Merged-Head: none
Fixed:
  - yuv_camera_frame_source_web.dart: copyTo пишет в JS-массив и байты читаются из него (под dart2wasm
    Uint8List.toJS — копия, и кадр остался бы нулевым); мёртвое поле _animationFrame удалено (запасной путь через
    requestAnimationFrame исполнитель убрал, requestVideoFrameCallback есть во всех текущих браузерах);
    оба catch (_) получили комментарий по решению 3.
  - CHANGELOG.md: загрузчик на package:web и новая зависимость web (Scope).
Blocking: none
Advisory: в lib/src/yuv/impl/web/** и трёх web-тестах остался ignore_for_file: avoid_web_libraries_in_flutter —
  они на dart:js_interop, подавление, вероятно, лишнее; вне Scope. Попутные правки web.ps1 по делу: Start-WebDriver
  раньше ловил исключение самой проверки в цикле ожидания драйвера и повторял её; git add --refresh перед dry-run.
```
`dart:html` в lib/, example/lib/ и example/integration_test/ — 0 совпадений. Перепрогон Reviewer после правок:
`example/` `flutter analyze` — no issues, `flutter test` — 39 passed, `flutter build web` — PASS. Браузерную пробу
после правок не перезапускал: правки — комментарии, удаление мёртвого поля и буфер copyTo, который под dart2js
делит память с Uint8List; полный `tool/ci/web.ps1` с camera smoke прошёл у Executor на 2ddf677.
