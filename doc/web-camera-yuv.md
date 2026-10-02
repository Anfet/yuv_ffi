# Кадры веб-камеры в исходном формате (WEB 4)

Вопрос: стоит ли Web-источнику камеры example (`example/lib/camera/impl/yuv_camera_frame_source_web.dart`)
брать кадр через `VideoFrame.copyTo()` **без** `format` — в исходном YUV — вместо нынешнего `format: 'BGRA'`
(запасной — `RGBA`).

**Ответ: не переходить сейчас.** Камера действительно отдаёт `NV12`, и получить его дешевле, чем BGRA, но на Web
шейдер выключен, и показ YUV-кадра стоит в 4 раза дороже показа BGRA. Путь YUV в сумме в 2,5 раза медленнее.
Вернуться к вопросу после WEB 5, если шейдер на Web заработает.

## Окружение

| | |
| --- | --- |
| Машина | Windows 10, Intel Core i9-13980HX |
| Браузер | Chrome 154.0.8037.98, окно (не headless), CanvasKit по умолчанию |
| Сборка | `flutter build web --release` (dart2js), Flutter 3.44.9 |
| Реальная камера | встроенная `Integrated Webcam (0bda:555d)`, 1280×720, 30 к/с |
| Фейковая камера | Chrome `--use-fake-device-for-media-stream` (`fake_device_0`), 1280×720, 20 к/с |
| Кадр | 1280×720 (запрос `ideal` 1280×720 выполнен точно) |

Mac не снимался: реальная камера на Windows была доступна (порядок площадок — карточка WEB 6).

## Что отдаёт камера (WEB 6)

| | Реальная камера | Фейковая камера |
| --- | --- | --- |
| `format` | `NV12` | `NV12` |
| `codedWidth × codedHeight` | 1280 × 720 | 1280 × 720 |
| `visibleRect` | 0, 0, 1280 × 720 | 0, 0, 1280 × 720 |
| `displayWidth × displayHeight` | 1280 × 720 | 1280 × 720 |
| `allocationSize()` без опций | 1 382 400 = 1280·720·1,5 | то же |
| `PlaneLayout` Y | offset 0, stride 1280 | то же |
| `PlaneLayout` UV | offset 921 600, stride 1280 | то же |

Раскладка плотная: строки без выравнивания, UV сразу за Y. Такой кадр собирается в
`YuvImage.nv12(..., layout: YuvPlaneLayout.preserve)` без копирования с перестройкой.

## Стоимость по подсистемам

Медианы, мс на кадр 1280×720. Захват — реальная камера (WEB 6, 10 прогревов + 60 кадров); импорт и показ —
синтетические кадры (WEB 7, WEB 8). Все три — одна машина и один Chrome. Время фейковой камеры в выводы не входит.

| Шаг | Путь YUV (NV12) | Путь BGRA (сейчас) |
| --- | --- | --- |
| `copyTo` (WEB 6) | 4,3 (p90 7,6) | 10,3 (p90 21,2) |
| импорт в `YuvImage` (WEB 7) | 1,4 | 1,6 |
| показ: `YuvFrameRenderer.upload()` (WEB 8) | 57,9 | 13,9 |
| **итого** | **63,6** | **25,8** |

Вариант `RGBA` в `copyTo` стоит столько же, сколько `BGRA` (10,1 мс); импорт I420 — столько же, сколько NV12.

Почему показ YUV дорогой — разбивка `upload()` (повтор Reviewer, 10 прогревов + 30 замеров):

| Формат | `toBgraBytes()` в WASM | декод в `ui.Image` | `upload()` целиком |
| --- | --- | --- | --- |
| I420 | 38,4 | 11,5 | 50,3 |
| BGRA | 2,0 | 11,6 | 13,8 |

На Web `YuvFrameRenderer.hasShader` всегда `false` (WEB 1): YUV-кадр сначала переводится в BGRA в WASM, затем
декодируется так же, как BGRA. Перевод — ~38 мс, больше бюджета кадра при 30 к/с (33 мс). Для сравнения, native
на Windows переводит кадр 1080p за ~30 мс (`doc/perf-findings.md`), то есть 720p — около 13 мс: WASM медленнее
примерно в 3 раза.

Оговорки:
- В WEB 6 не записано, сдвигался ли порядок трёх `copyTo` на одном кадре; первый `copyTo` может оплачивать чтение
  кадра из GPU. На вывод не влияет: путь BGRA — то же копирование плюс конверсия в браузере, а решает разница на
  показе (44 мс), а не на захвате (6 мс).
- Таймер браузера огрублён до 0,1 мс; разницы меньше этого шага в импорте нет.

## Рекомендация

Критерий (карточка WEB 4): переходить, если исходный формат — `I420` или `NV12` и путь YUV по медиане не медленнее
пути BGRA больше чем на 10 %. Формат подходит (`NV12`), но путь YUV медленнее в 2,5 раза (63,6 против 25,8 мс).

**Не переходить сейчас.** Web-источник остаётся на `copyTo(format: 'BGRA')` с запасным `RGBA` и canvas-путём для
браузеров без `MediaStreamTrackProcessor`.

**Когда вернуться:** после WEB 5. Если шейдер на Web заработает, показ YUV перестанет переводить кадр в BGRA на CPU
(−38 мс), и путь YUV, по этим числам, станет дешевле BGRA: ~4,3 + 1,4 + декод упакованных плоскостей против
25,8 мс. Тогда переход будет выглядеть так: `copyTo(buffer)` без `format` в буфер `allocationSize()`;
`YuvImage.nv12`/`i420` по возвращённым `PlaneLayout` с `YuvPlaneLayout.preserve`; для других форматов (RGB,
`I420A`, `I422`, `I444`, `format == null`) — нынешний BGRA-путь. Это стоит проверить и на камере Mac: её формат
здесь не снимался.

Отдельно от решения: перевод YUV → BGRA в WASM в 3 раза медленнее native и сам по себе кандидат на ускорение
(WEB 2 — оценка Web против native).

## Браузеры

Только Chrome. В Firefox и Safari `MediaStreamTrackProcessor` в главном потоке нет — источник уже идёт через canvas
(`drawImage` + `getImageData`, RGBA), и вопрос исходного формата там не возникает.

## Источники

- WebCodecs: [`VideoFrame.copyTo()`](https://www.w3.org/TR/webcodecs/#dom-videoframe-copyto),
  [`PlaneLayout`](https://www.w3.org/TR/webcodecs/#dictdef-planelayout),
  [`VideoPixelFormat`](https://www.w3.org/TR/webcodecs/#enumdef-videopixelformat).
- MDN: [`VideoFrame.copyTo()`](https://developer.mozilla.org/en-US/docs/Web/API/VideoFrame/copyTo),
  [`MediaStreamTrackProcessor`](https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrackProcessor).
- Сырые строки замеров — отчёты карточек WEB 6, WEB 7, WEB 8 (в git: `git show 66b3fb4:tasks/0.5.0/WEB-6.md` и т. д.).
