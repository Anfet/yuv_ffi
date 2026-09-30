# yuv_ffi: проваленные test cases

Этот файл — единый журнал фактически воспроизведённых падений. План исправлений
и владельцы задач находятся в `todo.md` либо `todo-waitlist.md`.

После независимого принятия fix-задачи ревьюер удаляет связанную запись целиком:
строку сводки и полную секцию, если она есть. Журнал содержит только актуальные
падения; доказательства принятого исправления находятся в task commit, tests и
Git history.

## Статусы

- `OPEN` — падение воспроизводится, исправление не принято.
- `IN FIX` — связанная задача находится в работе.
- `READY FOR RETEST` — исправление готово, нужен независимый повторный прогон.
- `WONTFIX` — только по явному решению владельца с записанным обоснованием.

## Сводка

| Failure ID | Case ID | Backend | Статус | Приоритет | Fix task | Кратко |
|---|---|---|---|---|---|---|
| F-009 | WEB-PLANAR-REFERENCE-001 | Web/WASM Chrome | RESOLVED | P1 | YUV-48 (`4ac9c37`) | Oracle shift и example manifest синхронизированы; Web matrix 119/119 |
| F-013 | REFERENCE-GENERATOR-DRIFT-001 | native VM (tool) | RESOLVED | P3 | YUV-49 | Generator воспроизводит committed `manifest.json`, включая `tolerances.effectPlanar`/`tolerances.blurPlanar` (F-011/F-012) |

## Текущее состояние reference matrix

- Source: `test/assets/test_pattern_512.png`
- Source SHA-256: `a48d5d2959a4d86f3f036fd704acc3726a12aaa66de825f738b3fa8b7e5f631a`, подтверждён YUV-10.
- Manifest: `test/reference/test_pattern_512/manifest.json`, 119 cases, SHA-256 `4f268ee88535fe1c9384a8b9144078dea77bc7803e7969e9b6bff02bb3bb35de`.
- Native reference run, 2026-09-20 (после YUV-44 fix commit): 119/119 cases passed,
  0 failed. YUV-42 (BGRA mean blur), YUV-43 (I420/NV21 blur, включая принятое
  решение по F-011 — `tolerances.blurPlanar`) и YUV-44 (effects/BGRA↔YUV
  conversions, включая принятое решение по F-012 — `tolerances.effectPlanar`)
  приняты и закрыты. Полная native reference matrix: 0 failed.
- Web reference run: частичный, 2026-09-14. Исполнено 19/119, passed 7, failed 12,
  остальные 100 не исполнены из-за обрыва (F-010).
- Web reference run, 2026-09-22 (YUV-40): **119/119 executed**, passed 59, failed 60.
  Обрыв F-010 не воспроизведён — полный failure log впервые получен. Детали в
  разделе F-010 ниже; данные о конкретных failed cases относятся к F-009 и
  будут классифицированы в YUV-13.
- Web reference run, 2026-09-22 (YUV-12, после task commit YUV-47 `bf8368d` и
  bindings-audit commit `e803d9c`): **119/119 executed**, passed 59, failed 60 —
  **идентичный список 60 failed case IDs**, что и в прогоне YUV-40 выше. WASM
  пересобран на HEAD `e803d9c` (`bash ./tool/wasm/build_wasm.sh`, exit 0),
  sha256 `20f72c397f4e53f0cba6f49145ff9e03efeb7599cd78b476026d00730d07461c`.
  Подтверждает, что I420/NV21 web-расхождение (F-009) не зависит от изменений
  YUV-47 (padded box blur) и воспроизводится стабильно на текущем коде.
  Детали прогона в разделе F-009 ниже (подраздел «Повторный прогон YUV-12»).
- Историческое обоснование (первый 2026-09-19 аудит на неисправленном коде,
  88/119; полная диагностика YUV-11) — в git history и предыдущих ревизиях
  этого файла.
- Последняя сверка полноты: native matrix сверена YUV-11; общую native/Web сверку выполнит YUV-13 после YUV-12.

Пока YUV-10…YUV-13 не выполнены, отсутствие asset-specific записей ниже не означает отсутствие дефектов.

## YUV-13 — сверка покрытия manifest × native × Web, 2026-09-22

- Commit: `f3c89c0` (HEAD на момент сверки; тот же commit, на котором получен
  последний Web-прогон YUV-12).
- Manifest: `test/reference/test_pattern_512/manifest.json`, 119 cases,
  проверено программным извлечением `id` каждого case — 119 уникальных ID,
  дублей нет.

### Native

Локальный прогон `flutter test test/reference_native_conversions_test.dart
--reporter expanded` на временно собранной MSVC Release DLL (CMake x64
generator, без подмены компилятора; `src/CMakeLists.txt` без изменений; DLL
собрана в scratch-каталоге, скопирована в игнорируемый корневой
`yuv_ffi.dll` только на время прогона и удалена сразу после):
**121/121 passed, 0 failed** (119 reference matrix cases + 2 harness/gate
assertions). Совпадает с ранее зафиксированным native-результатом после
YUV-42/43/44 (`0 failed`). Полный лог сохранён в сессии инженера.

### Web

Использован уже принятый прогон YUV-12 (раздел F-009 ниже, подраздел
«Повторный прогон YUV-12») — тот же HEAD `f3c89c0`/`e803d9c`, повторный
`flutter drive` не запускался по решению инженера: свежий прогон на этом же
коде уже есть, а DWDS/chromedriver handshake воспроизводимо flaky (~29%
success rate, см. F-010 rework #1-#3), повторный запуск не добавил бы новой
информации к сверке покрытия. Результат: **119/119 executed, 59 passed / 60
failed**.

### Сверка manifest × native × Web

Программно сопоставлены 119 manifest ID с 60 web-failed ID из прогона
YUV-12: все 60 присутствуют в manifest, дублей нет, все 60 — исключительно
I420/NV21 (конструирование, операции над I420/NV21, либо конвертация из
I420/NV21 в BGRA); ни один чистый BGRA8888 case не входит в failed-список.
Оставшиеся 59 manifest ID — passed на Web. Native покрывает все 119 ID без
пропусков (0 failed, 0 skipped).

**Missing case (manifest без native/Web результата):** нет. Все 119 ID имеют
и native, и Web результат.

### Классификация failed cases — rework 2026-09-22, доказанный root cause

Первая сдача этой карточки объединила все 60 web-failed ID под F-009 по
недоказанной гипотезе («construction ломается на Web, всё остальное
наследует»). Ревью справедливо вернуло это: `YuvImageState` конструктор при
явно переданных `planes` — общий для Web/native код без platform-branch
(`lib/src/yuv/shared/yuv_image_state.dart:36-52`), так что гипотеза не могла
быть верна как написана, а `FORMAT-TO-I420-NV21-*` в самой первой (частичной,
2026-09-14) записи F-009 показывал geometry mismatch (`Expected: <256>,
Actual: <512>`), необъяснённый construction-дефектом.

Разбор проведён заново с живыми данными из реального Chrome, а не только по
pass/fail логу. Собран test-only диагностический таргет
`example/integration_test/yuv13_web_diagnostic_test.dart` (не входит в
production/CI, оставлен как evidence до решения ревьюера об удалении),
прогнан 5 раз через `tool/wasm/yuv40_web_matrix_probe.ps1`
(`chromedriver-win64 153.0.8010.52`, `flutter drive -d chrome`) — все валидные
попытки дали `flutter_exit=0`. Логи: `tool/wasm/out/yuv13_diag_attempt{1,2,4,5}.log`
(gitignored, локально в checkout).

**Найденный root cause: платформенно-зависимая семантика `>>` для
отрицательных `int` в тестовом ораkуле, не в production Web-backend.**

`test/helpers/reference/test_pattern_reference.dart` (и его верифицированно
идентичная copy `example/integration_test/helpers/reference/
test_pattern_reference.dart`, diff — только doc-комментарий) вычисляет
chroma и YUV→RGBA decode через:

```dart
int _chromaU(int red, int green, int blue) => _clip(((-38 * red - 74 * green + 112 * blue + 128) >> 8) + 128);
int _chromaV(int red, int green, int blue) => _clip(((112 * red - 94 * green - 18 * blue + 128) >> 8) + 128);
// Yuv420Frame.decode(): output[...] = _clip((298 * c + 409 * e + 128) >> 8); // c/d/e могут быть отрицательными
```

Прямой замер `-1 >> 8` и других отрицательных значений в одном и том же коде:

| Платформа | `-1 >> 8` | `-256 >> 8` | `-999999 >> 8` |
|---|---|---|---|
| Native VM (`dart run`, локально) | `-1` | `-1` | `-3907` |
| Web (Chrome, этот же диагностический тест, `attempt5`) | `4294967295` | `4294967295` | `4294963389` |

VM даёт истинный знаковый арифметический сдвиг; Web (dart2js/DDC) отдаёт
результат как unsigned 32-bit (`0xFFFFFFFF` = `4294967295` для `-1`).
`_clip` затем `.clamp(0, 255)` превращает это в `255` — что и наблюдалось как
`ff`-байты в хвостах U/V-плоскостей при диагностике `CONSTRUCT-I420-TIGHT`
(`tool/wasm/out/yuv13_diag_attempt2.log`: `tail=ff ff 80 c0 c0 c0 ff ff ...`).

Дополнительно подтверждено на том же прогоне:

- `decodePng` детерминирован на Web (два независимых вызова на одних байтах
  дают одинаковый хэш) — исключает недетерминизм PNG-декодера как причину.
- Y-плейн (`_luma`, только положительные коэффициенты `66/129/25`) совпадает
  побайтово между Web и manifest — подтверждает, что дефект специфичен именно
  для отрицательных промежуточных сумм, которые встречаются только в
  chroma-формулах и в `decode()`.
- Round-trip: my `I420.decode()` (через тот же испорченный на Web оракул) не
  совпадает с manifest's `i420_decoded.png` — ожидаемо, так как оба они
  прогоняются через одну и ту же дефектную функцию, но на разных платформах.

**Вывод: все 60 web-failed ID объясняются одной доказанной причиной — не
production-дефектом `yuv_web.dart`/WASM, а платформенной несовместимостью
самого тестового оракула.** Production Web-backend не выполняет цветовую
арифметику в Dart вообще: `toBgra8888()` для BGRA — чистое копирование байт
(`_state.packedBgraBytes()`), а I420/NV21 конверсии полностью делегированы
WASM (`ccall` в `yuv_web.dart`), скомпилированному из C через emscripten, где
`>>` на `int32_t` сохраняет корректную знаковую семантику. Ни один найденный
failed case не проходит через Dart-арифметику production-кода со знаковым
сдвигом — вся цепочка расхождений объясняется тем, что **ожидаемые значения**
(построенные тестовым оракулом на Web) сами испорчены, а не тем, что
production-код дал неверный результат.

Это не разбито на отдельные failure ID по группам (construction/geometry/
metrics), поскольку все три ранее замеченных "группы" — проявления одной и
той же причины на разных стадиях сравнения (construction time для
CONSTRUCT-*, exact-hash comparison для FORMAT-TO-*/geometry cases, tolerance
comparison для Output/Effect/Blur cases, куда испорченные ожидаемые значения
попадают через `decode()`).

Не проверено и не входит в scope этой сверки: действительно ли WASM-путь
(C-код) даёт побитово идентичный результат native FFI-пути для I420/NV21 —
это отдельное утверждение, которое требует собственного evidence (не может
быть выведено из одного факта "оракул неверен на Web"), и оценивается новой
fix-задачей ниже.

### Итоговая сводка (для DoD YUV-13)

| Метрика | Значение |
|---|---|
| Manifest cases | 119 |
| Native executed/passed/failed/skipped | 121/121/0/0 (119 matrix + 2 harness) |
| Web executed/passed/failed/skipped | 119/119/0/0 |
| Manifest cases без native/Web результата | 0 |
| Unresolved failure IDs | — |

**F-009 закрыта YUV-48 (`4ac9c37`).** Историческая fix task: **YUV-48** (см. `todo.md`) —
исправить `>>`-семантику в `test_pattern_reference.dart` (оба места:
`test/helpers/...` и `example/integration_test/helpers/...`, синхронно),
перегенерировать manifest, подтвердить Web-матрицу заново. YUV-48 не относится к native C или к production Web-backend — native C
менять не требует (scope: только `test/helpers/`, `example/integration_test/
helpers/`, `test/reference/test_pattern_512/manifest.json`,
`tool/reference/generate_test_pattern_references.dart` при необходимости).

---

## F-009 — Web/WASM расходится с эталоном на I420 и NV21

- Case ID: `WEB-PLANAR-REFERENCE-001`
- Статус: RESOLVED (`4ac9c37`, 2026-09-22)
- Обнаружено: 2026-09-14
- Commit: `2ae1dc3` (HEAD), последний commit по C-исходникам `3524f05`
- Backend: Web / WASM, Chrome 153.0.8010.37 на Windows x64
- Environment: Flutter 3.38.10, Dart 3.10.9
- WASM: `assets/wasm/yuv_ffi.wasm` sha256
  `61b6c52d9aca319ed575cf403729d8684fa8ea5cc99f4d36abc638523e495569`;
  `yuv_ffi.js` sha256 `96576b243c3407fbb934a523a149fede8fbb0894491b3b3c702ee3921b8331a3`.
  Пересобран `bash ./tool/wasm/build_wasm.sh` (exit 0), diff артефактов пустой.
- Source image: `test/assets/test_pattern_512.png`, sha256
  `a48d5d2959a4d86f3f036fd704acc3726a12aaa66de825f738b3fa8b7e5f631a`
- Suite: `example/integration_test/reference_web_conversions_test.dart`
- Fix task: YUV-48 (классификация и root cause — YUV-13; исправление
  тестового оракула — YUV-48)

### Воспроизведение

```powershell
Push-Location example
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/reference_web_conversions_test.dart -d chrome
Pop-Location
```

Провенанс прогона: `YUV-12 web provenance: kIsWeb=true, cases=119`.

### Факт

Исполнено 19/119 (обрыв — см. F-010), из них passed 7, failed 12.
Все 12 падений — I420/NV21. Все 5 BGRA-кейсов прошли с `mae=0.000 max=0`,
включая padded, то есть Web/BGRA совпадает с эталоном побайтово.

Failed case IDs:

```text
CONSTRUCT-I420-TIGHT       CONSTRUCT-I420-PADDED
OUTPUT-TO-BGRA-I420-TIGHT  OUTPUT-TO-BGRA-I420-PADDED
CONSTRUCT-NV21-TIGHT       CONSTRUCT-NV21-PADDED
OUTPUT-TO-BGRA-NV21-TIGHT  OUTPUT-TO-BGRA-NV21-PADDED
FORMAT-TO-BGRA-I420        FORMAT-TO-BGRA-NV21
FORMAT-TO-I420-BGRA-TIGHT  FORMAT-TO-I420-NV21-TIGHT
```

Три различимые группы:

1. **Расхождение при конструировании.** `CONSTRUCT-I420-TIGHT` падает в
   `_assertPlaneReference` по sha256 плоскости:
   expected `e2b4a0192095db1c5f96b4bfc524c22d283181d3921b07409dc58db99fe3c5e2`,
   actual `bda27b969a63634a0a6125bdcadfa453f1d0c8efe3495747ed1b3d68fda73462`,
   differ at offset 0. Никакая операция ещё не выполнялась — расходится сама
   раскладка планарных плоскостей.
2. **Метрики вне допуска `yuvRoundTrip`** (`mae<=18`, `max<=160`):
   - `OUTPUT-TO-BGRA-I420-TIGHT`: `mae=44.469 max=255 p99=255 outside=101888 alpha=0`
   - `FORMAT-TO-BGRA-I420`: `mae=44.469 max=255 p99=255 outside=101888 alpha=0`
   - `FORMAT-TO-I420-BGRA-TIGHT`: `mae=10.233 max=144 p99=144 outside=17408 alpha=0`
3. **Геометрия.** `FORMAT-TO-I420-NV21-TIGHT`: `Expected: <256>, Actual: <512>`
   в `_assertPlaneReference`.

### Границы утверждения

Сравнение native/Web не проводилось: это задача YUV-13. Native-прогон той же
матрицы (Windows x64) дал 65/119 passed, поэтому часть этих падений может
совпадать с уже известными native-дефектами, а часть быть Web-специфичной.
Без полного Web-прогона (блокирует F-010) разделить их нельзя.

Production behavior и tolerances в рамках YUV-12 не менялись.

### Повторный прогон YUV-12, 2026-09-22 — полный failure log на актуальном HEAD

- Commit: `e803d9c` (после task commit YUV-47 `bf8368d` — padded pixelStride>1
  box blur gap-byte contract test — и bindings-audit cleanup `e803d9c`, оба
  вне scope YUV-12, закоммичены по прямому указанию инженера перед прогоном).
- Backend: Web / WASM, Chrome 153.0.8010.53 на Windows x64.
- Environment: Flutter 3.44.9 (`D:\.important\flutter-3.44\flutter\bin\flutter`).
- WASM: пересобран `bash ./tool/wasm/build_wasm.sh` на этом HEAD, exit 0.
  `assets/wasm/yuv_ffi.wasm` sha256
  `20f72c397f4e53f0cba6f49145ff9e03efeb7599cd78b476026d00730d07461c`,
  закоммичен в `f3c89c0`.
- WebDriver: `chromedriver-win64` 153.0.8010.52 (Chrome for Testing), запущен
  локально на порту 4444.
- Команда:

  ```powershell
  Push-Location example
  flutter drive --driver=test_driver/integration_test.dart --target=integration_test/reference_web_conversions_test.dart -d chrome --headless
  Pop-Location
  ```

- Результат: `YUV-12 web provenance: kIsWeb=true, cases=119`, затем
  `YUV-12 summary: executed=119 passed=59 failed=60 ids=[...]` — **тот же
  список 60 ID**, что зафиксирован в подразделе F-010 rework выше
  (`CONSTRUCT-I420-TIGHT` … `FLUTTER-TO-IMAGE-NV21`). Полный per-case лог
  (`YUV-12 case PASSED`/`FAILED` для каждого из 119 cases) сохранён.
- Три подтверждённые группы падений те же, что в первом частичном прогоне
  (construct-time sha256 mismatch, метрики вне допуска `yuvRoundTrip`,
  geometry mismatch на `FORMAT-TO-I420-NV21-*`), теперь подтверждённые для
  всех 60 cases, а не только для исходных 12.
- Все 59 passed cases — исключительно BGRA (construct/input/output, tight и
  padded), включая `FORMAT-TO-NV21-BGRA-TIGHT`, ранее обрывавший прогон
  (F-010) — теперь PASSED.
- Production behavior и tolerances не менялись. WASM пересборка — единственное
  разрешённое Scope действие, применена без изменения C/Web кода.

---

### Resolution — 2026-09-22

YUV-48 (`4ac9c37`) replaced platform-dependent oracle shifts with `_shr8` and
synchronized the stale example manifest with the canonical F-011/F-012 planar
tolerances. The terminal macOS Chrome/WASM rerun is retained at
`tool/wasm/out/yuv48_macos_full_run_rerun_20260922.log`: `executed=119`,
`passed=119`, `failed=0`, followed by `All tests passed!`. No failed IDs remain.

---
## F-013 — `generate_test_pattern_references.dart --check` падает на чистом HEAD

- Case ID: `REFERENCE-GENERATOR-DRIFT-001`
- Обнаружено: 2026-09-22, в рамках работы над YUV-48 (проверка DoD-шага
  «перегенерировать `manifest.json`»), не связано с самой задачей YUV-48.
- Воспроизведено на чистом `f3c89c0` без каких-либо правок YUV-48
  (`git stash` перед прогоном, `git checkout --` после): `dart run
  tool/reference/generate_test_pattern_references.dart --check` завершается
  с `Reference fixture is out of date` и exit 1.

### Причина

`test/reference/test_pattern_512/manifest.json` содержит секции
`tolerances.blurPlanar` и `tolerances.effectPlanar`, добавленные вручную
(не инструментом) в commit `8f6ced3` как принятые инженером решения по
F-011/F-012, и 20 case-записей (Blur/Effect группы), у которых поле
`comparison` вручную выставлено в `blurPlanar`/`effectPlanar` вместо
`blur`/`yuvRoundTrip`. Текущий `tool/reference/generate_test_pattern_references.dart`
никогда не содержал строк `blurPlanar`/`effectPlanar` (проверено `git log`/
`git show` по всей истории файла) — он статически пишет `comparison: 'blur'`
для всех Blur-кейсов и `yuvRoundTrip`/`nv21RoundTrip` для Effect-кейсов.
При запуске без `--check` инструмент перезаписывает manifest и **удаляет**
обе секции допусков вместе с их developer-rationale текстом и понижает
допуск 20 кейсов до более узкого — то есть тихо отменяет принятые решения
F-011/F-012, если кто-то запустит генератор без ручного восстановления.

### Проверено, что не пересекается с YUV-48

Regenerate с оригинальным (до правки YUV-48) кодом оракула и с
исправленным дают побайтово идентичные SHA-256 по всем artifacts — сам
`>>`-баг ни на одном artifact текущего `test_pattern_512.png` не меняет
результат (отрицательная промежуточная сумма реальными пикселями фикстуры
не достигается). Расхождение в `manifest.json` при regenerate — только
удаление `blurPlanar`/`effectPlanar` секций и понижение `comparison` у
20 case-записей; сами хэши артефактов, метрики и все остальные 99 записей
не меняются.

### Статус

`RESOLVED` в YUV-49: generator содержит обе tolerance sections и policy для
20 planar cases; `dart run tool/reference/generate_test_pattern_references.dart --check`
завершается с code 0 и сообщает `Reference fixture is byte-identical.`

---

## F-010 — прогон Web-матрицы обрывается без сообщения на 20-м case

- Case ID: `WEB-MATRIX-ABORT-001`
- Статус: OPEN
- Обнаружено: 2026-09-14
- Commit: `2ae1dc3` (HEAD)
- Backend: Web / WASM, Chrome 153.0.8010.37 на Windows x64
- Environment: Flutter 3.38.10, Dart 3.10.9
- Suite: `example/integration_test/reference_web_conversions_test.dart`
- Fix task: YUV-40 (изолированная диагностика; не production fix)

### Факт

Цикл по 119 cases печатает результат каждого case через `debugPrint` и ловит
все исключения через `catch (error, stackTrace)`. После 19-го case
(`FORMAT-TO-I420-NV21-TIGHT`, зафиксирован как FAILED) 20-й case
`FORMAT-TO-NV21-BGRA-TIGHT` не напечатал **ни PASS, ни FAIL**, и исполнение
прекратилось. Оставшиеся 100 cases не исполнены.

Признаки:

- строки `YUV-12 summary ... executed=... passed=... failed=...` в логе нет —
  цикл не дошёл до конца;
- счётчик runner остался `+0`, финального `All tests passed` / `Some tests
  failed` нет;
- в логе нет ни timeout, ни pending timer, ни потери соединения с debug service;
- прогон завершился сам: `Application finished.`, затем `EXIT=1`.

### Гипотеза

Так как per-case `catch` перехватывает любое `Object`, отсутствие записи
означает, что исполнение прервано некатчабельно для этого блока: WASM trap либо
`Error`, убивающий isolate. Для подтверждения нужен прицельный прогон только
`FORMAT-TO-NV21-BGRA-TIGHT` с захватом консоли браузера.

### Влияние

Блокирует DoD YUV-12: полный failure log недостижим, 100/119 cases не имеют
результата. До устранения нельзя ни закрыть YUV-12, ни выполнить сверку
native/Web (YUV-13).

---

### Диагностика YUV-40, 2026-09-22 — обрыв не воспроизведён

- Commit: `2a576e6` (HEAD на момент прогона). **Working tree не чистый**:
  незакоммиченные изменения в `src/yuv/nv21/nv21_box_blur.c` и
  `src/yuv/yuv420/yuv420_box_blur.c` — только doc-комментарии (контракт
  `src == dst`), поведение не меняют; `test/planar_box_mean_blur_contract_test.dart`
  и `tool/verify_bindings_audit.dart` изменены отдельно, blur/conversion логики
  не касаются. Native C, влияющий на BGRA↔NV21/I420, не менялся.
- Backend: Web / WASM, Chrome 153.0.8010.53 на Windows x64
- Environment: Flutter 3.44.9, Dart 3.12.2 (основной прогон по карточке,
  3.38 не использовался)
- WASM: `assets/wasm/yuv_ffi.wasm` sha256
  `bb2401bc1067624d79d1f45c18a0755e7f73b1d7803a385468d936d86edeea36`;
  `yuv_ffi.js` sha256 `2a6f77b728d5019dcf0a4a8d0553b785110ac47d2afa0016686db7dd2fa378fe`.
  **Не пересобран** этим прогоном — `emcc` недоступен на машине; это
  закоммиченные артефакты, `git status --short assets/wasm/` пуст, последний
  commit по WASM `274d8cd`.
- WebDriver: на машине не было `chromedriver`; скачан `chromedriver-win64`
  153.0.8010.52 с Chrome for Testing (ближайшая доступная сборка к
  установленному Chrome 153.0.8010.53), запущен локально на порту 4444.

#### Шаг 1-2 — изолированный target

Добавлен `example/integration_test/yuv40_web_matrix_abort_test.dart`:
воспроизводит только пару control (`_bgra(source).toYuvI420()`) +
candidate (`_bgra(source).toYuvNv21()`), с маркерами `debugPrint`/`console.log`
до и после каждого вызова, второй вариант (`YUV40_VARIANT=after-nv21-to-i420`)
вставляет NV21→I420 predecessor перед candidate, как в позиции 19→20 исходной
матрицы.

```powershell
Push-Location example
& 'D:\.important\flutter-3.44\flutter\bin\flutter.bat' drive --driver=test_driver/integration_test.dart --target=integration_test/yuv40_web_matrix_abort_test.dart -d chrome
Pop-Location
```

- `isolated` (default): все маркеры напечатаны, `candidate after toYuvNv21`
  дошёл до конца (`format=nv21 planes=2 yBytes=262144 uvBytes=131072`),
  `00:00 +2: All tests passed!`, `Application finished.` — обрыв не
  воспроизведён.
- `after-nv21-to-i420`: то же самое, все маркеры включая predecessor и
  candidate напечатаны, `All tests passed!` получен. Отдельное наблюдение:
  `flutter drive` не завершил сам процесс после печати результата (завис на
  закрытии WebDriver-сессии, не на тесте) — процесс остановлен вручную после
  подтверждения, что весь тестовый сценарий и `All tests passed!` уже в логе.
  Это gap в самом harness/driver teardown, не в F-010.

#### Шаг вне исходного плана — повторный прогон полной матрицы

План диагностики (шаги 1-4) предполагал точечную изоляцию 20-го case. Так как
изолированный target не воспроизвёл обрыв, для проверки was это
окружение-специфично или устранено, была перезапущена оригинальная полная
матрица:

```powershell
Push-Location example
& 'D:\.important\flutter-3.44\flutter\bin\flutter.bat' drive --driver=test_driver/integration_test.dart --target=integration_test/reference_web_conversions_test.dart -d chrome
Pop-Location
```

Результат: **`YUV-12 web provenance: kIsWeb=true, cases=119`**, все 119 case
исполнены (полный список от `CONSTRUCT-BGRA8888-TIGHT` до
`INPUT-ODD-CUSTOM-STRIDE-NV21-127X255`), включая ранее обрывавший
`FORMAT-TO-NV21-BGRA-TIGHT`, который теперь **PASSED**
(`mae=0.000 max=0 p99=0 outside=0`). Итог: `YUV-12: 60/119 case(s) failed`,
то есть **59 passed / 60 failed**, `08:55 +1 -1: Some tests failed.` — суммарный
runner-статус получен, обрыва без сообщения нет.

Полный список 60 failed case ID (для F-009/YUV-13, не для этой записи):
`CONSTRUCT-I420-TIGHT, CONSTRUCT-I420-PADDED, OUTPUT-TO-BGRA-I420-TIGHT,
OUTPUT-TO-BGRA-I420-PADDED, CONSTRUCT-NV21-TIGHT, CONSTRUCT-NV21-PADDED,
OUTPUT-TO-BGRA-NV21-TIGHT, OUTPUT-TO-BGRA-NV21-PADDED, FORMAT-TO-BGRA-I420,
FORMAT-TO-BGRA-NV21, FORMAT-TO-I420-NV21-TIGHT, FORMAT-TO-NV21-I420-TIGHT,
FORMAT-TO-I420-NV21-PADDED, FORMAT-TO-NV21-I420-PADDED, CHROMA-SWAP-NV21-1,
CHROMA-SWAP-NV21-2, CHROMA-SWAP-I420-1, CHROMA-SWAP-I420-2,
GEOMETRY-CROP-I420-INNER, GEOMETRY-CROP-I420-CLAMPED, GEOMETRY-CROP-I420-EMPTY,
GEOMETRY-ROTATE-I420-0, GEOMETRY-ROTATE-I420-90, GEOMETRY-ROTATE-I420-180,
GEOMETRY-ROTATE-I420-270, GEOMETRY-FLIP-H-I420, GEOMETRY-FLIP-V-I420,
GEOMETRY-CROP-NV21-INNER, GEOMETRY-CROP-NV21-CLAMPED, GEOMETRY-CROP-NV21-EMPTY,
GEOMETRY-ROTATE-NV21-0, GEOMETRY-ROTATE-NV21-90, GEOMETRY-ROTATE-NV21-180,
GEOMETRY-ROTATE-NV21-270, GEOMETRY-FLIP-H-NV21, GEOMETRY-FLIP-V-NV21,
EFFECT-GRAYSCALE-I420, EFFECT-GRAYSCALE-NV21, EFFECT-BLACKWHITE-I420,
EFFECT-BLACKWHITE-NV21, EFFECT-NEGATE-I420, EFFECT-NEGATE-NV21,
BLUR-GAUSSIANBLUR-I420-GAUSSIAN_DEFAULT, BLUR-GAUSSIANBLUR-NV21-GAUSSIAN_DEFAULT,
BLUR-GAUSSIANBLUR-I420-GAUSSIAN_R3_S2, BLUR-GAUSSIANBLUR-NV21-GAUSSIAN_R3_S2,
BLUR-BOXBLUR-I420-BOX_DEFAULT, BLUR-BOXBLUR-NV21-BOX_DEFAULT,
BLUR-BOXBLUR-I420-BOX_FULL, BLUR-BOXBLUR-NV21-BOX_FULL, BLUR-BOXBLUR-I420-BOX_RECT,
BLUR-BOXBLUR-NV21-BOX_RECT, BLUR-MEANBLUR-I420-MEAN_DEFAULT,
BLUR-MEANBLUR-NV21-MEAN_DEFAULT, BLUR-MEANBLUR-I420-MEAN_FULL,
BLUR-MEANBLUR-NV21-MEAN_FULL, BLUR-MEANBLUR-I420-MEAN_RECT,
BLUR-MEANBLUR-NV21-MEAN_RECT, FLUTTER-TO-IMAGE-I420, FLUTTER-TO-IMAGE-NV21`.

Все failed cases — I420/NV21 (BGRA всегда passed), консистентно с F-009.

#### Ограничение evidence

Driver-процесс полной матрицы не дописал `Application finished.`/`EXIT=` в
лог после `Some tests failed.` — тот же teardown-gap, что в изолированном
`after-nv21-to-i420` прогоне. Точный exit code процесса не зафиксирован: я
остановил зависший процесс вручную после того, как summary и полный per-case
лог уже были в выводе. Само исполнение теста (все 119 case, summary,
финальный runner-статус `Some tests failed.`) подтверждено логом целиком —
именно это отсутствовало в 2026-09-14 прогоне и составляет предмет F-010.

#### Вывод

Обрыв F-010, зафиксированный 2026-09-14 на Chrome 153.0.8010.37 / Flutter
3.38.10, **не воспроизводится** на Chrome 153.0.8010.53 / Flutter 3.44.9 с
текущими WASM-артефактами (`274d8cd`). Причина не установлена методом
"поймать trap маркерами" — обрыва не случилось, ловить было нечего. Возможные
объяснения (не проверены раздельно, только перечислены):

1. Обрыв зависел от конкретной версии Chrome (`.37` vs `.53`) — например,
   V8/WASM engine bug, исправленный апстримом между версиями браузера.
2. Обрыв зависел от версии Flutter/DDC/debug-service (`3.38.10` vs `3.44.9`),
   не от WASM или production-кода.
3. Обрыв был устранён побочно одной из принятых между 2026-09-14 и сейчас
   задач (YUV-42/43/44 и др.), хотя они не были нацелены на Web/WASM harness.

Различить эти гипотезы в рамках Scope YUV-40 (test-only, без production
изменений) не представлялось возможным без второй машины/старой версии
Chrome — сохраняю как открытый вопрос для инженера, не как доказанный root
cause.

#### Follow-up

- F-010 переводится в `READY FOR RETEST`: обрыв не подтверждён, но и не
  доказано, что он не может повториться (root cause не установлена, только
  наблюдение "сейчас не воспроизводится").
- Полный failure log для YUV-12 получен этим прогоном — исходный DoD YUV-12
  (полный прогон 119/119 с provenance и per-case логом) фактически выполнен
  как побочный результат этой диагностики; должен быть явно принят/переоткрыт
  инженером, а не тихо закрыт этой запиской.
- Driver teardown gap (`Application finished.` не печатается после
  `All tests passed!`/`Some tests failed.`) — отдельное, некритичное
  наблюдение; не блокирует чтение результатов теста, но искажает "процесс не
  завершился" как сигнал. Не заводил отдельный F-XXX: не влияет на
  production behavior и не является тестовым провалом.

#### Rework 2026-09-22 — воспроизводимый exit code и проверка гипотез

Ревью вернуло карточку: независимая проверка зависла на
`Waiting for connection from debug service on Chrome...`, exit code не был
получен ни разу в исходной сдаче (процессы останавливались вручную).

Собран самодостаточный PowerShell-runner (чистит stale `chromedriver`/
orphaned webdriver Chrome-сессии перед стартом, поднимает свежий
`chromedriver`, запускает `flutter drive ... --timeout=120`, гарантированно
останавливает driver в `finally`, пишет `EXIT_CODE=<code>` в лог). 7
последовательных прогонов изолированного target этим runner'ом:

- **5 из 7** зависли на `Waiting for connection from debug service on
  Chrome...` (33–55s, без дальнейшего прогресса) — тот же симптом, что
  получил ревьюер.
- **2 из 7** дошли до `All tests passed!` с полным per-case логом.

Это новый, отдельный от F-010 дефект: **intermittent Chrome/chromedriver/DWDS
debug-service handshake**, ~29% success rate на этой машине в этой сессии,
воспроизводится независимо от production YUV-кода и от того, какой target
запускается. Полная таблица «гипотеза → команда → наблюдение» (5 гипотез,
включая stale `.dart_tool/chrome-device` профиль, orphaned webdriver-сессии,
version mismatch Chrome `.53`/chromedriver `.52`, driver teardown gap) — в
`todo.md`, раздел «Результат повторной сдачи, 2026-09-22 (rework)» под
карточкой YUV-40.

Итог не изменился: обрыв F-010 (тихий обрыв без PASS/FAIL посреди 119-кейсовой
матрицы) не воспроизведён ни разу за все попытки, включая rework. Новый
harness-флаки (connect-hang) — не F-010: другой симптом, но объясняет
результат независимой проверки ревьюера.

#### Rework #2, 2026-09-22 — runner в репозитории, root cause найдена

Прошлая сдача вернулась: `run_yuv40_probe.ps1` жил вне репозитория (нельзя
повторить), а evidence содержал противоречие — таблица утверждала, что оба
"успешных" прогона не записали `EXIT_CODE=`, но ниже был заявлен штатный
`EXIT_CODE=0`. Разбор показал источник противоречия: тот `0` был exit-кодом
Bash-обёртки инструмента (`[exited with code 0]`), а не `flutter drive` —
подмена понятий, `$LASTEXITCODE` за `Tee-Object`-пайпом давал недостоверный
сигнал.

Исправлено: **`tool/wasm/yuv40_web_matrix_probe.ps1` теперь в репозитории**
(test-only, не в pipeline/CI). Exit code читается напрямую через
`Process.ExitCode` дочернего `cmd.exe /c <flutter.bat> ...` (не
`$LASTEXITCODE`), с отдельным файлом результата, который не делит
файловый handle с redirected stdout. Каждый прогон даёт ровно один
terminal result: `flutter_exit=<n>` или `timeout` (опционально с суффиксом
причины при детектируемой сигнатуре в логе).

10 попыток этим раннером против изолированного target: **0 из 10** дали
`flutter_exit=<n>` — все либо зависли (`timeout`, 9/10), либо (1/10, попытка
5) дошли до `Application finished.` в логе, но столкнулись с известным
багом .NET `Process.ExitCode` для `Start-Process -FilePath <bat>`,
исправленным сразу после обнаружения переходом на `cmd.exe /c`. Таблица
всех 10 попыток с `-TimeoutSeconds` и классификацией — в `todo.md`, раздел
«Результат повторной сдачи (rework #2), 2026-09-22» под YUV-40.

**Root cause подтверждена документально для одного failure mode.** Отдельный
verbose-прогон (`flutter drive ... -v`) дал полный traceback вместо голого
зависания: DWDS (`package:dwds`) кидает `AppConnectionException` в
`DevHandler._startLocalDebugService`, за которым следует
`VmService proxy responded with an error: {..., message: The stream 'Timer'
is not supported on web devices}` и `Shutting down Chromium.` — но даже
после этого лог не содержит `exiting with code <n>`: сам процесс `flutter
drive` не доходит до чистого завершения даже когда внутренняя ошибка уже
поймана. Это объясняет одновременно белое пустое окно Chrome, замеченное
пользователем во время прогонов (страница открывается по `localhost:PORT`,
но DDC-модули инжектируются DWDS повторно без успешного запуска рантайма),
и то, почему ни разу не был получен чистый `flutter_exit`.

Не установлено: единая ли эта причина для всех 10 таймаутов, или разные
попытки зависали в разных точках DWDS handshake (часть — на "Waiting for
connection", часть — позже, на "Debug service listening", без появления
`AppConnectionException` в логе к моменту таймаута). Раннер v2 детектит эту
сигнатуру автоматически, но за пределами этого прогона она не появилась ни
разу дополнительно — то есть доказанная причина покрывает не все случаи.

Итог по F-010 не изменился: не воспроизведён ни разу за все 17 суммарных
попыток (7 из rework #1 + 10 из rework #2). Обнаруженный DWDS-дефект — другой,
самостоятельный симптом с полным traceback, не тихий обрыв.

#### Rework #3, 2026-09-22 — безопасный cleanup, устранён третий result, найдена реальная гонка

Rework #2 вернулся с четырьмя замечаниями: cleanup мог убить чужой
chromedriver (глобальный `Stop-Process -Force` по имени процесса, без
привязки к PID/порту этого прогона); код допускал скрытый третий result
`exit_code_unavailable`, хотя контракт заявлял только два; раннер оставался
untracked, хотя был назван закоммиченным; raw logs лежали в session-scoped
`/tmp`, недоступном для повторной проверки.

Все четыре исправлены в `tool/wasm/yuv40_web_matrix_probe.ps1`:

- cleanup теперь останавливает только PID, которые сам прогон породил
  (`$driverProc`, `$flutterProc`, и Chrome-процессы с `ParentProcessId`
  равным PID именно этого `$driverProc`), плюс явный `Test-PortInUse`
  guard перед стартом — при занятом порту скрипт отказывается запускаться
  вместо борьбы за него;
- при `ExitCode -eq $null` скрипт `throw`-ит вместо тихого третьего
  результата — при отладке этого пути обнаружена и исправлена настоящая
  причина: задокументированная .NET-гонка `WaitForExit(Int32)` без
  follow-up parameterless `WaitForExit()` (подтверждено напрямую: attempt 11
  дал throw именно тогда, когда собственный лог flutter уже показывал
  `exiting with code 0` — процесс завершился чисто, PowerShell прочитал
  ExitCode слишком рано);
- логи и result-файлы сохраняются в `tool/wasm/out/` внутри checkout
  (добавлено в `.gitignore`), а не в session temp.

5 новых попыток (attempts 11-15): 1 throw (гонка, тут же исправлена), 4
`timeout` (разные точки DWDS handshake, согласуется с rework #2). F-010
по-прежнему не воспроизведён ни разу за все 22 суммарные попытки. Полная
таблица, детали каждого исправления и запрос к ревьюеру — в `todo.md`,
раздел «Результат повторной сдачи (rework #3), 2026-09-22» под YUV-40.

---

**YUV-11 — native reference matrix (2026-09-13).** Первый детальный аудит
119-кейсовой матрицы (54 failed / 65 passed на тот момент), давший начало
YUV-42/43/44/05 и другим fix-задачам; полный текст сокращён здесь после
приёмки хвоста задач, которые он поднял. Детали — в git history этого файла.

---

## F-XXX — <краткое название>

- Case ID: <ID из reference manifest или infrastructure ID>
- Статус: OPEN
- Обнаружено: YYYY-MM-DD
- Commit: <полный hash>
- Backend: <Native/Web + OS/browser/arch>
- Environment: <Flutter/Dart/compiler versions>
- Binary/WASM provenance: <как собран и из какого commit>
- Source image: test/assets/test_pattern_512.png
- Source SHA-256: <hash>
- Operation: <method + parameters + input format>
- Fix task: <YUV-XX или NOT ASSIGNED>

### Команда
<точная воспроизводимая команда>

### Ожидалось
<expected format/dimensions/hash/bytes>

### Получено
<actual format/dimensions/hash/bytes>

### Метрики
- MAE: <value>
- Maximum channel error: <value>
- Percentile error: <value>
- Pixels outside threshold: <count/total>
- Alpha mismatches: <count>

### Артефакты
- Expected: <path вне build/>
- Actual: <path вне build/>
- Diff: <path вне build/>
- Log: <path вне build/ или inline excerpt>

### Resolution
- Fix commit: не заполнен
- Retest command/result: не заполнен
```

