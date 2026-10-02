# WEB 1 — Веб: шейдер и кадры камеры в YUV без RGBA
**Status:** BLOCKED · **Tier:** T1 · **Owner:** SHADER 3 · **Depends On:** SHADER 3 · **Probe:** windows

#### Goal
Исследование и, где проба это позволяет, включение: (1) шейдер `YuvFrameRenderer` (SHADER 2) на Web;
(2) кадры веб-камеры в исходном I420/NV12 через `VideoFrame.copyTo()` вместо RGBA. Web остаётся частичным
WASM-бэкендом (`AGENTS.md`); задача не заявляет паритет с native.

Параллельная задача: не блокирует этапы. Стартует после слияния пула «показ кадров» (там SHADER 1…3).

#### Architect Decision
1. **Шейдер на Web — решает проба.** Шейдерная проба SHADER 3 запускается в Chrome через `flutter drive`
   (renderer CanvasKit; skwasm — если `flutter build web --wasm` собирает example). Все случаи с `max_diff <= 1` →
   в `YuvFrameRenderer` снимается выключатель `kIsWeb`, Web-вариант пробы добавляется в Web-матрицу
   `tool/ci/web.ps1` (`Assert-WebSourceMatrix`, список `aggregate`). Иначе выключатель остаётся, расхождения
   (случай, renderer, максимум) — в отчёт и dartdoc.
2. **`VideoFrame.copyTo()` в исходном формате — только исследование.** Web-источник CAMERA 1 уже читает кадр через
   `MediaStreamTrackProcessor` + `copyTo` с RGBA/BGRA-форматом. Проверить в Chrome на этой машине и на Mac:
   `VideoFrame.format` кадра камеры; `copyTo` без `format` (исходные плоскости) и его `PlaneLayout`; стоимость на
   кадр против нынешнего RGBA-пути (720p, медиана 60 кадров). Сборка `YuvImage` из полученных плоскостей и показ —
   прототип вне коммита. Вывод и рекомендация — `doc/web-camera-yuv.md`; изменение Web-источника — отдельная
   карточка Architect по этой рекомендации.
3. Источники фактов — спецификация WebCodecs (`VideoFrame.copyTo`, `PlaneLayout`) и MDN; ссылки — в документ.

#### Scope
- `lib/src/widgets/yuv_frame_renderer.dart` — только снятие выключателя `kIsWeb` по решению 1.
- Web-вариант шейдерной пробы (`example/integration_test/`, суффикс `_web_test`) и строка в `tool/ci/web.ps1`.
- `doc/web-camera-yuv.md`; `README.md` и `CHANGELOG.md` — только если шейдер на Web включён.

#### Constraints
- Native, `lib/src/yuv/impl/web/**` и WASM-сборку не трогать.
- Браузерные прогоны — по `todo.md` («Окружение → ChromeDriver», «Mac»); вердикт `flutter drive` — по строке
  `All tests passed` с негативным контролем.

#### Definition of Done
- [ ] Шейдерная проба на Web выполнена; шейдер включён (проба прошла) или оставлен выключенным с записанными
      расхождениями.
- [ ] `doc/web-camera-yuv.md`: формат кадра, `PlaneLayout`, стоимость `copyTo` в исходном формате против RGBA,
      рекомендация.
- [ ] `tool/ci/web.ps1` проходит.

#### Validation
Ключи: `lib/*` → `vm example`, `tool/ci/web.*` → `web`, `example/integration_test/*` → `all`, `doc/*` → —.

- `pwsh -File tool/ci/web.ps1`, `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/example.ps1`.
- Шейдерная Web-проба с негативным контролем (перепутанные U/V во временной копии).
- Probe `windows`: `flutter test --tags probe`.

#### Executor Report
#### Review
