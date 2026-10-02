# WEB 4 — Кадры веб-камеры в исходном формате: исследование
**Status:** BLOCKED · **Tier:** T1 · **Owner:** WEB 1 · **Depends On:** WEB 1 · **Probe:** none

#### Goal
Web-источник камеры (CAMERA 1, WEB 3) получает кадр через `MediaStreamTrackProcessor` и `VideoFrame.copyTo()` с
`format: 'BGRA'` (запасной — `RGBA`): браузер сам переводит кадр в RGB, а показ идёт BGRA-путём. Если `copyTo` без
`format` отдаёт исходные I420/NV12, кадр можно не конвертировать в браузере и, при варианте A WEB 1, показывать
шейдером. Задача — выяснить, так ли это и стоит ли переходить. Только исследование: изменение источника — отдельная
карточка Architect по рекомендации.

Параллельная задача: этапы не блокирует. Пул `PAR-WEB`: WEB 1 → WEB 4 (рекомендация учитывает исход WEB 1).

#### Architect Decision
1. **Что выяснить** — для реальной камеры и для фейковой камеры Chrome:
   - `VideoFrame.format`, `codedWidth/Height`, `visibleRect`, `displayWidth/Height` кадра;
   - `copyTo(buffer)` без `format`: `allocationSize()`, возвращённые `PlaneLayout` (`offset`, `stride` по плоскостям);
   - стоимость на кадр, медиана 60 кадров после 10 прогревов, 720p (или ближайшее, что даёт камера; фактическое — в
     документ): `copyTo` исходный формат / `BGRA` / `RGBA`; импорт в `YuvImage` — `YuvImage.i420`/`nv12` с
     `layout: YuvPlaneLayout.preserve` по `PlaneLayout` против нынешнего BGRA-импорта; показ одного кадра через
     `YuvFramePresenter(useShader: true)` в обоих вариантах.
2. **Как мерить.** Прототип — отдельная точка входа в example или страница, **не коммитится**; сборка Web — release
   (`flutter build web`, dart2js), отдача — любым статическим сервером; числа — в консоль браузера.
   - Реальная камера — Chrome на Mac (`todo.md`, «Окружение → Mac»), запуск с
     `--use-fake-ui-for-media-stream` (авто-разрешение, камера настоящая).
   - Фейковая камера — Chrome на Windows с `--use-fake-device-for-media-stream`: только формат и `PlaneLayout`;
     скорость фейковой камеры в выводы не идёт.
   - Если на Mac Chrome не получает камеру через SSH (разрешение macOS на камеру): страницу открывает Engineer
     локально и присылает вывод консоли — команда и URL в отчёте.
3. **Документ** `doc/web-camera-yuv.md`: окружение (браузер, версия, ОС, камера), таблица фактов решения 1,
   таблица стоимостей, рекомендация с обоснованием — «переходить» (какой формат, какие браузеры, что с запасным путём,
   набросок изменений источника) или «не переходить» (почему). Источники — спецификация WebCodecs
   (`VideoFrame.copyTo`, `PlaneLayout`, `VideoPixelFormat`) и MDN, ссылками.

#### Scope
- `doc/web-camera-yuv.md`. Код прототипа — вне коммита.

#### Constraints
- `lib/`, native и Web-источник камеры не менять.
- Только Chrome; Firefox/Safari — строкой в документе, если `MediaStreamTrackProcessor` там нет.

#### Definition of Done
- [ ] `doc/web-camera-yuv.md` по решению 3: факты для реальной и фейковой камеры, стоимости, рекомендация.
- [ ] Если рекомендация «переходить» — в отчёте черновик Goal для следующей карточки (одна-две фразы).

#### Validation
Ключи: `doc/*` → —. Ветка пула — `all/PAR-WEB`.

- Прототип запускался: команды сборки и запуска, версия Chrome — в отчёт.

#### Executor Report
#### Review
