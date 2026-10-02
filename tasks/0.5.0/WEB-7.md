# WEB 7 — Web: стоимость импорта кадра в `YuvImage`
**Status:** TODO · **Tier:** T2 · **Owner:** — · **Depends On:** — · **Probe:** none

#### Goal
Подсистема импорта из исследования WEB 4. Сейчас Web-источник камеры отдаёт кадр как `YuvImage.bgra` +
`yPlane.assignFrom(bytes)` (`example/lib/camera/impl/yuv_camera_frame_source_web.dart`, `_deliverBgra`). Если
источник перейдёт на исходный YUV, кадр будет собираться как `YuvImage.i420`/`YuvImage.nv12` из плоскостей. Замерить
на синтетических кадрах, сколько стоит каждый импорт на Web. Камера не нужна. Захват — WEB 6, показ — WEB 8,
вывод — WEB 4.

Пул `PAR-WEB`, идёт параллельно WEB 6 и WEB 8.

#### Architect Decision
1. **Прототип** — `example/lib/web_import_probe_main.dart`. **Не коммитится**. Сборка — release, в свой каталог:
   `cd example && flutter build web --release -t lib/web_import_probe_main.dart -o build/web-web7`; отдача —
   статический сервер из `example/build/web-web7`. Перед замером — `await YuvFfi.initialize()`. Результат — строка
   `WEB7 RESULT <json>` в консоль и на страницу.
2. **Входные данные** — 1280×720, байты заполнены псевдослучайно один раз до замера, `Uint8List` в памяти Dart, как
   после `copyTo`:
   - I420: три плоскости, `stride` = ширина плоскости (1280 / 640 / 640);
   - I420 с выравниванием: `stride` 1344 / 704 / 704 (камеры часто выравнивают строки);
   - NV12: Y 1280 + UV 1280;
   - BGRA: 1280×720×4.
3. **Замер** — для каждого варианта 10 прогревов и 60 замеров, `performance.now()` вокруг одного импорта:
   - I420/NV12: `YuvImage.i420(...)`/`YuvImage.nv12(...)` с `planes` из `YuvPlane` (байты — срезы
     `Uint8List.sublistView` одного буфера по `offset`/`stride`, как после `copyTo`) и
     `layout: YuvPlaneLayout.preserve`;
   - BGRA: ровно как `_deliverBgra` — `YuvImage.bgra(w, h)`, `yPlane.assignFrom(bytes)`, `markDirty()`.
   На Web `YuvImage` держит плоскости в памяти Dart, в WASM данные уходят только при операции — она входит в показ
   (WEB 8), здесь не мерится. В результат — медиана и p90 по варианту.
4. **Где** — Chrome на Windows, **не headless**. Если WEB 6 сняла реальную камеру на Mac — тот же прототип и на Mac
   (`mac-run.sh`; камера не нужна, поэтому через SSH обычно работает; если Chrome на Mac не запускается из SSH —
   `AWAITING_EXTERNAL` с командой и URL для Engineer).

#### Scope
- Только раздел `#### Executor Report` этой карточки. Прототип — вне коммита.

#### Constraints
- `lib/`, native, Web-источник и шейдер не менять. Только Chrome, сборка dart2js; `--wasm` не входит.
- Параллельно с WEB 6 и WEB 8 в одной копии: не переключать ветку, коммитить только свою карточку
  (`git commit -- tasks/0.5.0/WEB-7.md`), чужие файлы не трогать.

#### Definition of Done
- [ ] Строки `WEB7 RESULT` — в отчёте целиком; ОС, Chrome (версия), машина.
- [ ] Прототипа нет в коммитах; свои временные файлы удалены.

#### Validation
Ключи: `tasks/*` → —. Ветка `all/PAR-WEB` в основной копии (D-22). CI-скрипты не нужны.

#### Executor Report
#### Review
