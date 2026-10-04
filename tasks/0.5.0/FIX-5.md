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

- REWORK: shader renderer получает синхронный снимок `frame.size` от `present()` и использует его при создании текстуры после декодирования; также самостоятельно захватывает размеры для прямых вызовов `upload()`. Добавлен тест повторного использования кадра с изменением размеров во время декодирования.
- Добавлен тест ошибки копирования при `useShader: true` во время BGRA fallback и проверки, что следующий кадр принимается и завершается.
- PASS: `flutter test test/yuv_frame_presenter_test.dart test/yuv_frame_renderer_test.dart test/public_surface_test.dart` — 15 тестов.
- PASS: `pwsh -File tool/ci/windows.ps1` — 20/20 проверок, 1 skipped, 0 failed.
- PASS: негативный контроль — временно восстановлена исходная последовательность (занятость до `toBgraBytes()`); тест упал на `isBusy == false` (exit 1). Исправленная реализация восстановлена, точечный набор повторён и прошёл 15/15.
- REWORK: восстановлена исходная публичная сигнатура `YuvFrameRenderer.upload(YuvImage frame)`; размеры теперь захватываются синхронно внутри renderer до копирования/упаковки. Shader fallback тест проверяет пиксель кадра через `RepaintBoundary.toImage()` без условного пропуска.
- PASS: `dart format --line-length 150` для четырёх изменённых Dart-файлов; `dart analyze lib test example/integration_test/presenter_shader_native_test.dart` — No issues found.
- PASS: `flutter test test/yuv_frame_presenter_test.dart test/yuv_frame_renderer_test.dart test/public_surface_test.dart` — 15/15; `pwsh -File tool/ci/vm.ps1` — 638/638, 0 skipped; `pwsh -File tool/ci/windows.ps1` — 134/134, 0 skipped, 0 failed; Windows build и 5 integration targets, включая `presenter_shader_native_test`, PASS.
- PASS: `bash tool/ci/scope_guard.sh 78eca6c6071004175431f58c27fc8101664d501b` → `all`; все обязательные команды для доступной Windows-машины выполнены.
- Примечание: негативный контроль BGRA-теста на исходной последовательности выполнен ранее и записан выше; текущий тест shader fallback отдельно доказывает показ принятого следующего кадра пикселем.

#### Review

**PASS по коду, 04.10.2026; проверено рабочее дерево поверх `ba9b6df`, включая доработки renderer и тестов.** Обе предыдущие находки закрыты: публичная сигнатура `upload(YuvImage frame)` сохранена, размеры захватываются синхронно до декодирования; shader BGRA fallback проверяет фактический пиксель следующего кадра без условного пропуска. Новых блокирующих замечаний к коду нет.

Независимо воспроизведены: точечный набор presenter/renderer/public surface — 15/15; `vm.ps1` — 638/638; `windows.ps1` — 134/134, Windows release build и все пять integration targets PASS, включая настоящий shader-путь с ошибками размера и упаковки. `dart analyze lib test example/integration_test/presenter_shader_native_test.dart` — PASS; проверка форматирования пяти Dart-файлов без записи — 0 изменений.

Негативный контроль выполнен с отдельной временной копией presenter из `78eca6c`, без замены рабочих файлов: новый BGRA-тест упал на `isBusy == false` (фактически `true`, exit 1). Дополнительная временная проверка чтения `frame.size` подтвердила, что тест shader BGRA fallback вызывает ветку загруженного renderer; она прошла. Временные файлы удалены.

**Статус остаётся REVIEW до фиксации доработки в git и проверки чистого SHA**, как требует Validation и правило 4 в `todo.md`: `ba9b6df` не содержит проверенную доработку. `scope_guard.sh <base>` печатает `all` для общего диапазона FIX 5–8 и текущих изменений CI; полный межплатформенный гейт этим локальным ревью не подтверждён.

**REWORK, 04.10.2026; проверены изменения рабочего дерева поверх `ba9b6df`.** `YuvFrameRenderer.upload()` получил второй публичный параметр `frameSize`, хотя Constraints запрещает менять публичные сигнатуры. Сохранить `upload(YuvImage frame)` и захватывать размер синхронно внутри renderer; `present()` может сохранить свой снимок размера для геометрии.

Тест `shader BGRA fallback errors leave the presenter free for the next frame` не проверяет изображение: при `useShader: true` getter `presenter.image` всегда возвращает `null`, поэтому ветка `if (presenter.image != null)` недостижима. Проверять фактический показ следующего кадра через виджет/пиксель либо иной наблюдаемый результат без условного пропуска. Точечные тесты 15/15 и `dart analyze lib test` прошли; эти проверки не обнаруживают нарушения контракта и слабую проверку результата.

**REWORK, 04.10.2026; проверен диапазон `78eca6c..c155637`.** В `YuvFrameRenderer.upload()` размеры `frame.width` и `frame.height` читаются в `.then` после возврата `present()`. Если вызывающий код сразу меняет или повторно использует кадр, текстура получает размеры уже изменённого кадра при прежних скопированных пикселях. Зафиксировать размеры синхронно до декодирования в shader и BGRA fallback; проверить повторное использование кадра тестом.

Также выполнить требуемый негативный контроль нового BGRA-теста на базовом коде и добавить тест ошибки `toBgraBytes()` в fallback при `useShader: true`, с проверкой следующего кадра. Текущий точечный прогон `flutter test test/yuv_frame_presenter_test.dart test/public_surface_test.dart` прошёл: 11/11.
