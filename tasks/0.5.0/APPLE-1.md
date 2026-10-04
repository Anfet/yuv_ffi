# APPLE 1 — Проверка работы на macOS и iOS
**Status:** REVIEW · **Tier:** T2 (T1 — если шейдерная проба на Metal разойдётся: отдельная карточка) · **Owner:** Executor · **Depends On:** — · **Probe:** none · **Base:** `6f71a45`

#### Goal
Последний прогон на Apple — `macos.sh` и `ios.sh` на `bae5ff8` (код `d3bb2cc`, этап 3). Всё, что добавили этапы 4 и
5 — геометрия кадра, YUV-шейдер на Metal/Impeller, презентер, камерный слой, вставка фрагмента, экран проверки, —
на macOS и iOS локально не запускалось. Задача — до релизного этапа понять и подтвердить, как пакет и example
работают на macOS и iOS. Сначала оценка (D-21): что сейчас происходит на Apple и как — грузится ли шейдер на
Metal/Impeller и сходится ли с CPU, каким путём идёт камера (BGRA или YUV), что делают презентер и захват кадра, — и
чем рискуем: что может не собраться, работать иначе, чем на Android/Windows, или не проверяться без устройства. Затем
проверка и, по рискам, исправления.

Этап 7 (D-21), после WEB 5: проверяет код после уборки этапа 6 и правки шейдера WEB 5, если она была.

#### Architect Decision
1. **Начало — итоги CI.** Executor разбирает macOS и iOS прогоны `ci/all/STAGE6` (первый запуск на Apple после
   этапа 3; оба зелёные) и, если WEB 5 меняла упаковку или шейдер, — прогоны `ci/macos/<метка>` и `ci/ios/<метка>` на базе пула.
   Красное в CI — первый пункт оценки.
2. **Оценка** — короткий раздел в отчёте: по каждому пункту Goal — что происходит, чем подтверждено (тест, лог,
   код), риск и как он проверяется.
3. **Проверки на Mac** (`todo.md`, «Окружение → Mac»; release-сборки на этом Mac виснут — поведенческие проверки в
   debug):
   - `bash tool/ci/macos.sh` и `bash tool/ci/ios.sh` целиком: SPM и CocoaPods, все `*_native_test.dart`, в том
     числе шейдерная проба SHADER 3 (`max_diff <= 1`), презентер и захват кадра;
   - камера на macOS: `example/lib/camera_desktop_smoke_main.dart` и камерный экран example в debug, снимок →
     редактор. Разрешение на камеру macOS даёт Engineer, если нужен GUI-доступ;
   - iOS: симулятор (камеры нет). iOS-устройство — только если Engineer его предоставит; иначе в отчёте
     ограничение «камера и экран проверки на iOS не проверены на устройстве».
4. **PASS:** оба скрипта зелёные локально, шейдерная проба на Metal `max_diff <= 1`, камера macOS показывает кадр и
   снимок открывается в редакторе.
5. **Дефекты:** исправление в пределах одного-двух файлов с ясной причиной — в этой карточке (со своим Probe по
   правилам `AGENTS.md`); крупнее или с выбором решения — отдельная карточка, Engineer решает, блокирует ли она
   релиз.

6. **`Package.swift` — решение Engineer (04.10.2026):** Flutter 3.44 предупреждает, что у SPM-пакета плагина нет
   зависимости на `FlutterFramework` («Plugin yuv_ffi has a Package.swift … missing a dependency on
   FlutterFramework»); соседнее предупреждение о плагинах без SPM Flutter прямо называет будущей ошибкой. Зависимость
   добавляется в этой карточке, вопреки ограничению на `darwin/`; проверка — `macos.sh` и `ios.sh` (SPM и CocoaPods).

#### Scope
Проверки и отчёт; исправления — по решению 5. Ограничения, которые остаются, — в README (раздел платформ) и
`example/README.md`.

#### Constraints
- Без правок `src/` и сборочной конфигурации Apple (`darwin/`, `Package.swift`, podspec) без отдельного решения
  в карточке.
- CI-скрипты `macos.sh`/`ios.sh` меняются, только если найденный дефект — в самом скрипте.

#### Definition of Done
- Оценка по всем пунктам Goal записана; риски с проверкой или с причиной, почему не проверены.
- PASS по решению 4 или каждый провал — исправлен либо вынесен в карточку.
- Ограничения Apple (симулятор без камеры, release-сборки на Mac и т. п.) — в README или `example/README.md`.

#### Validation
- Executor: решение 3 на Mac; при исправлениях — локальные проверки по ключам `bash tool/ci/scope_guard.sh <base>`.
- Reviewer: повтор шейдерной пробы на macOS и одного из скриптов по выбору; при исправлениях — CI-теги
  `ci/macos/APPLE-1`, `ci/ios/APPLE-1` на принятом SHA.

#### Executor Report
**Итог: PASS по решению 4**; найдено и исправлено 2 дефекта. Код — `0a7ac5a`, документы — до `HEAD` (база `6f71a45`).

**Оценка** (решение 2):
- *Шейдер на Metal/Impeller* — грузится и сходится с CPU: `shader_probe_native_test` PASS на macOS и iOS-симуляторе в
  `ci/all/WEB-5` (`6f71a45`, с правкой упаковки WEB 5) и `ci/macos|ios/APPLE-1` (`0a7ac5a`); на iPhone экран
  проверки — `shader: true`.
- *Путь камеры* — на iOS (`camera_avfoundation`) и macOS (`camera_desktop`) кадры приходят BGRA, поэтому камера идёт
  BGRA-путём; шейдер работает для I420/NV12 (редактор, презентер). Риск низкий.
- *Ориентация* — наш код на не-Android считает кадр прямым (`camera_orientation.dart`). На iPhone подтверждено:
  плагин сам поворачивает кадр (480×640 в портрете, 640×480 в альбоме) и зеркалит фронтальную камеру; ответы
  `landscape`, `mirror` — да. Запись в `example/README.md` («не проверено на устройстве») заменена.
- *Презентер и захват* — `presenter_shader_native_test`, `camera_capture_native_test` PASS на macOS и iOS; на
  iPhone `capture` — да (418×640, видимая часть кадра).
- *Сборка* — SPM и CocoaPods проходят в обоих скриптах. Риск: Flutter 3.44 предупреждал, что у SPM-пакета нет
  зависимости на `FlutterFramework` (соседнее предупреждение Flutter называет будущей ошибкой) — исправлено (решение 6).

**Проверки** (решение 3):
- `macos.sh`, `ios.sh` — через CI на раннере Mac (по SSH release-сборка виснет): [`ci/macos/APPLE-1`](https://github.com/Anfet/yuv_ffi/actions/runs/37156823727),
  [`ci/ios/APPLE-1`](https://github.com/Anfet/yuv_ffi/actions/runs/37156823976) на `0a7ac5a` — success; все
  `*_native_test` PASS, runtime-смоук — в режиме SPM и CocoaPods; предупреждения про `FlutterFramework` в логах нет.
  До правки — `ci/all/WEB-5` 9/9.
- Камера macOS (MacBook Pro, macOS 15.6.1, debug, по SSH через `open`): `camera_desktop_smoke_main.dart` — `SMOKE
  COMPLETE (5/5 frames, clean stop)`, встроенная FaceTime HD 640×480 BGRA, кадры с изображением; разрешение дал
  Engineer.
- Камера macOS в **release** (04.10.2026): `flutter build macos --release -t lib/camera_desktop_smoke_main.dart` по SSH
  прошёл за ~40 с (41 МБ) — зависание `gen_snapshot` не воспроизвелось; `SMOKE COMPLETE (5/5 frames, clean stop)`,
  BGRA 640×480 с изображением. Release-приложение — другой бинарник, macOS запросила разрешение камеры заново,
  Engineer подтвердил.
- iPhone (iOS 18.7.8, debug, `flutter run` запускал Engineer — подпись по SSH падает на `errSecInternalComponent`):
  DEVICE 1 — все шаги и ответы «да», 30 к/с на всех шагах (частота камеры), `face_ratio` 1,0 в портрете и альбоме,
  `shader: true`. Engineer: «картинка прекрасная — плавная».

**Дефекты:**
1. Рамка лица на экране проверки не сбрасывалась после шагов с лицом (на любой платформе) — рамка обнуляется в конце
   замера, поздний результат распознавания игнорируется (`device_check_screen.dart`). Повтор на iPhone — рамка
   исчезает. `flutter test test/device_check` 5/5, `example.ps1` PASS.
2. `Package.swift` без `FlutterFramework` — зависимость добавлена (решение 6); на Mac предупреждение исчезло,
   `yuv_ffi` нет в `Podfile.lock`, символы `_yuv_*_v1` в `yuv-ffi.framework` есть.

**Не дефекты / ограничения:**
- `PlatformException: No active stream to cancel` от `camera_avfoundation` 0.9.19 при старте — шум плагина при
  отмене ещё не начатого потока, кадры идут; в пакете не исправляется.
- `blur_ms_median 1074,9` и жёлтая плашка «Run this check in release mode» — debug-сборка, так задумано; скорость в
  критерий не входит. Release на iPhone не запускался (подпись по SSH недоступна — запускает Engineer).
- Редактор после снимка на iPhone отдельно не проверялся (шаг `capture` экрана проверки — да).
- Документы: `README.md` (ручные проверки iOS и macOS в таблице платформ), `example/README.md` (ориентация на iOS),
  `CHANGELOG.md` (`Package.swift`).

#### Review
