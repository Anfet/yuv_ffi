# WEB 8 — Web: стоимость показа кадра
**Status:** IN_PROGRESS · **Tier:** T2 · **Owner:** PAR-WEB · **Depends On:** — · **Probe:** none

#### Goal
Подсистема показа из исследования WEB 4. На Web шейдер выключен (WEB 1): `YuvFrameRenderer` показывает любой кадр
BGRA-путём, а I420/NV12 перед этим конвертируется в WASM. Замерить на синтетических кадрах, сколько стоит показ
I420, NV12 и BGRA. Камера не нужна. Захват — WEB 6, импорт — WEB 7, вывод — WEB 4.

Пул `PAR-WEB`, идёт параллельно WEB 6 и WEB 7.

#### Architect Decision
1. **Прототип** — `example/lib/web_present_probe_main.dart`. **Не коммитится**. Сборка — release, в свой каталог:
   `cd example && flutter build web --release -t lib/web_present_probe_main.dart -o build/web-web8`; отдача —
   статический сервер из `example/build/web-web8`. Перед замером — `await YuvFfi.initialize()` и
   `YuvFrameRenderer.load()`; в результат — `hasShader` (ожидается `false`). Результат — строка
   `WEB8 RESULT <json>` в консоль и на страницу.
2. **Входные данные** — готовые `YuvImage` 1280×720: I420, NV12, BGRA; псевдослучайные байты, созданы до замера.
3. **Замер** — для каждого формата 10 прогревов и 60 замеров:
   - `await renderer.upload(image)` — время до готовой текстуры, текстура освобождается;
   - кадр на экране: `YuvFramePresenter(useShader: true, onFramePresented: ...)` + `YuvFrameView` 1280×720 —
     время от `present(image)` до `onFramePresented`; следующий кадр подаётся только после колбэка.
   В результат — медиана и p90 по формату и шагу.
4. **Где** — Chrome на Windows, **не headless** (в headless рендер идёт без GPU, время не показательно). Если WEB 6
   сняла реальную камеру на Mac — тот же прототип и на Mac (`mac-run.sh`; если Chrome на Mac не запускается из SSH —
   `AWAITING_EXTERNAL` с командой и URL для Engineer).

#### Scope
- Только раздел `#### Executor Report` этой карточки. Прототип — вне коммита.

#### Constraints
- `lib/`, native, Web-источник и шейдер не менять; выключатель `kIsWeb` из WEB 1 не снимать. Только Chrome, сборка
  dart2js (CanvasKit по умолчанию); `--wasm` не входит.
- Параллельно с WEB 6 и WEB 7 в одной копии: не переключать ветку, коммитить только свою карточку
  (`git commit -- tasks/0.5.0/WEB-8.md`), чужие файлы не трогать.

#### Definition of Done
- [ ] Строки `WEB8 RESULT` — в отчёте целиком; ОС, Chrome (версия), машина, `hasShader`.
- [ ] Прототипа нет в коммитах; свои временные файлы удалены.

#### Validation
Ключи: `tasks/*` → —. Ветка `all/PAR-WEB` в основной копии (D-22). CI-скрипты не нужны.

#### Executor Report
Windows, Chrome 154.0.8037.98, this machine; release dart2js, CanvasKit default, 1280x720 synthetic images:

```text
WEB8 RESULT {"os":"Windows","chrome":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36","machine":"this machine","hasShader":false,"uploadMs":{"I420":{"median":57.8000000002794,"p90":59.799999999813735},"NV12":{"median":57.89999999990687,"p90":59.799999999813735},"BGRA":{"median":13.899999999906868,"p90":15.100000000093132}},"presentMs":{"I420":{"median":63.90000000037253,"p90":70.3000000002794},"NV12":{"median":63.799999999813735,"p90":67.59999999962747},"BGRA":{"median":18.5,"p90":24.799999999813735}}}
```

For each format, the result contains 10 warmups and 60 samples. The temporary probe built successfully in `example/build/web-web8`; its source was removed. No package files changed.

#### Review
