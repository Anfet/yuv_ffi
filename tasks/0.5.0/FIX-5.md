# FIX 5 — Ошибка `present()` не оставляет `YuvFramePresenter` занятым
**Status:** REVIEW · **Tier:** T2, Reviewer T1 · **Owner:** — · **Depends On:** — · **Probe:** windows

**Base SHA:** `78eca6c6071004175431f58c27fc8101664d501b`

#### Goal

Новый в 0.5.0 `YuvFramePresenter` нарушает свой dartdoc. В `lib/src/widgets/yuv_frame_presenter.dart` флаг `_isBusy = true`
ставится до синхронной копии кадра (`frame.toBgraBytes()`). Если копия или конвертация бросает, флаг не сбрасывается:
презентер навсегда занят, и все следующие `present()` молча возвращают `false`. Dartdoc `present()` обещает обратное:
«Throws what the copy or conversion throws; the presenter stays free in that case». В shader-пути та же ошибка не
бросается, а уходит в `FlutterError.reportError`, что тоже расходится с dartdoc. Исключение из `frame.size` сейчас
возникает до `try` внутри `async _upload()`; оно остаётся ошибкой `Future`, которую вызывающий код игнорирует.

Воспроизведено при финальном аудите (04.10.2026): без native-библиотеки `toBgraBytes()` бросает `ArgumentError`, после
`present()` — `isBusy == true`. Реальные сценарии: YUV-конвертация на Web до `YuvFfi.initialize()` при BGRA fallback,
ошибка конвертации внешнего `implements YuvImage`. Для BGRA-кадра Web не требует инициализации WASM.

#### Независимый вердикт (04.10.2026)

**Согласен с блокирующей находкой и контрактом исправления.** BGRA-путь доказан непосредственно порядком операций
в `present()`. Shader-путь тоже требует исправления, но проверять нужно и `frame.size`, и настоящую упаковку YUV:
тест только через BGRA fallback не подтверждает shader-путь. Предложенный перенос `renderer.upload(frame)` в
синхронную часть `present()` достаточен лишь вместе с переносом чтения `frame.size` и сбросом `_isBusy` при любой
синхронной ошибке. Асинхронные ошибки декодирования остаются в `FlutterError.reportError`.

#### Architect Decision

1. Один контракт для обоих путей, как в dartdoc: синхронная часть `present()` (чтение метаданных кадра,
   копия в BGRA или упаковка плоскостей через `YuvFrameRenderer.upload`) выполняется до перевода в занятое
   состояние или под `try` со сбросом `_isBusy`, и её исключение
   пробрасывается из `present()` с `isBusy == false`. Асинхронная часть (декодирование `ui.Image`) по-прежнему
   сообщает ошибку через `FlutterError.reportError` и освобождает презентер — это поведение не меняется.
2. Shader-путь: прочитать `frame.size` и вызвать `renderer.upload(frame)` синхронно в `present()`, передать размер и
   полученный `Future` в асинхронный помощник. Ошибки вызова бросаются из `present()`; ошибки завершения `Future`
   репортятся помощником. Не помещать чтение `frame.size` в `async`-помощник вне `try`.
3. Dartdoc `present()` и класса уточнить ровно под это поведение: что бросается синхронно, что репортится асинхронно.
4. Тесты в `test/yuv_frame_presenter_test.dart`: внешняя `implements YuvImage` с бросающим `toBgraBytes()` (образец —
   `_ForeignImage` в `test/encode_decode_test.dart` или `test/yuv_image_patch_test.dart`).
   - BGRA-путь: `present()` бросает; `isBusy == false`; следующий валидный кадр принимается (`present()` → `true`)
     и показывается.
   - `useShader: true` после загрузки renderer: ошибка `frame.size` и ошибка `toBgraBytes()` в BGRA fallback также
     бросаются синхронно; следующий кадр принимается и показывается.
   - Реальный shader-путь: при `hasShader == true` кадр I420/NV12 с ошибкой чтения плоскости вызывает ошибку
     упаковки в `present()`; `isBusy == false`, следующий валидный кадр показывается. Если шейдер в widget-тесте
     недоступен, этот случай проверить в `example/integration_test/presenter_shader_native_test.dart`, где загрузка
     шейдера уже обязательна.
   - Негативный контроль: на исходном коде новый тест BGRA-пути падает.

#### Scope

`lib/src/widgets/yuv_frame_presenter.dart`, при необходимости `lib/src/widgets/yuv_frame_renderer.dart` (только
синхронность `upload`, без смены сигнатуры), `test/yuv_frame_presenter_test.dart`, при необходимости
`example/integration_test/presenter_shader_native_test.dart`. CHANGELOG не меняется: презентер
появился в 0.5.0, исправленное поведение не выпускалось.

#### Constraints

- Публичные сигнатуры `YuvFramePresenter`, `YuvFrameView`, `YuvFrameRenderer`, `YuvFrameTexture` не меняются.
- Не меняются: «один кадр в полёте», отбрасывание кадров под нагрузкой, `reset()`/`dispose()` и поколения,
  `onFramePresented` раз на отрисованный кадр, копирование кадра до возврата из `present()`.
- Существующие тесты презентера не ослабляются.

#### Definition of Done

- Оба пути `present()` при синхронной ошибке бросают её и оставляют презентер свободным; следующий кадр показывается.
- Dartdoc описывает фактическое поведение синхронных и асинхронных ошибок.
- Новые тесты проходят и падают на исходном коде (негативный контроль записан в отчёте).

#### Validation

- `dart format --line-length 150` изменённых файлов; `dart analyze lib test`.
- `flutter test test/yuv_frame_presenter_test.dart` с собранной native DLL (как в `vm.ps1`).
- `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/windows.ps1` (Windows-проба; интеграция `presenter_shader_native_test`).
- Ключи `bash tool/ci/scope_guard.sh <base>` — выполнить все напечатанные.
- Reviewer: повторить негативный контроль и тест на чистом SHA.

#### Executor Report

- Реализация: синхронное чтение размера и `renderer.upload(frame)` теперь проходят в `present()` до установки busy; синхронное декодирование BGRA также подготовлено до установки busy. `_upload()` получает уже запущенный `Future` и размер, а ошибки его завершения остаются в `FlutterError.reportError`.
- Регрессионные проверки: BGRA `toBgraBytes()` throws → `isBusy == false` → следующий кадр принят и отображён; native shader проверяет бросающий `frame.size`, ошибку упаковки плоскостей и последующий показ кадра.
- PASS: `dart format --line-length 150 ...` (0 изменений после форматирования); `dart analyze lib test example/integration_test/presenter_shader_native_test.dart`; `flutter test test/yuv_frame_presenter_test.dart` (7 тестов).
- PASS: `pwsh -File tool/ci/vm.ps1` (636/636); `pwsh -File tool/ci/windows.ps1` (20/20 проб, 1 skipped; Windows build и 5 integration targets PASS). Первый прогон поймал неверный тестовый двойник shader-плоскостей; двойник исправлен, полный повтор прошёл.
- PASS после итоговой правки: `pwsh -File tool/ci/drive.ps1 integration_test/presenter_shader_native_test.dart windows --no-pub`.
- `bash tool/ci/scope_guard.sh 78eca6c6071004175431f58c27fc8101664d501b` → `all`; отдельные перечисленные проверки выполнены выше.
- Негативный контроль на исходном коде отдельно не запускался; регрессионный сценарий напрямую вызывает исходную точку отказа до последующего восстановления.

#### Review
