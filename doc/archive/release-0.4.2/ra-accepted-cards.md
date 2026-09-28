# Принятые карточки предрелизного цикла 0.4.2

Полные тексты карточек, отчётов исполнителей и ревью, перенесённые из `pre-release-todo.md` после приёмки. Краткие записи — в `COMPLETION.md`.

### RA-05 — Зелёная джоба `analyze-and-test-vm (3.38.10)`
**Status:** DONE · **Tier:** T3 · **Owner:** Luna · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** — · **Rejection Count:** 0

#### Problem / Goal
Джоба падала на Flutter 3.38.10 из-за `deprecated_member_use_from_same_package`. Первопричина и итог проверки записаны в Executor Report ниже.

#### Architect Decision
`test/plane_row_copy_contract_test.dart` имеет `// ignore_for_file: deprecated_member_use_from_same_package`: тест намеренно проверяет внутренний транспорт, который ключуется устаревшим `YuvFileFormat`. На Flutter 3.38.10 этот же analyzer также сообщает о шести других намеренных same-package deprecation calls в legacy API и тестах; чтобы сохранить ограничение «не менять `lib/`», запускать `flutter analyze --no-fatal-infos lib test`. Warnings и errors остаются блокирующими; текущий Flutter 3.44.9 выводит для тех же файлов 0 info.

#### Constraints / Non-goals
Не менять `lib/`, не поднимать нижнюю границу SDK, не убирать 3.38.10 из матрицы. Если `flutter test` на 3.38.10 падает из-за реальной несовместимости пакета (а не теста) — ARCHITECT_REQUIRED с логом: это решение Engineer о границе `flutter: '>=3.38.0'`.

#### Definition of Done
- [x] Обе матричные джобы `analyze-and-test-vm` зелёные в CI-run `36413754181`
- [x] Нет изменений в `lib/`; устаревшее внутреннее использование остаётся видимым в CI, но analyzer info не валит только эту проверку

#### Validation / Testing
`flutter analyze --no-fatal-infos lib test`; ссылка на зелёный CI-run.

#### Executor Report
Добавлен `// ignore_for_file: deprecated_member_use_from_same_package` в `test/plane_row_copy_contract_test.dart`. CI run `36411031370` на Flutter 3.38.10 нашёл ещё шесть same-package deprecation infos в трёх legacy-файлах `lib/` и двух тестах; на 3.44.9 эти же info отсутствуют. Из-за запрета менять `lib/` шаг Analyze запускается с `--no-fatal-infos`; warnings и errors остаются блокирующими. Новый CI run `36413754181` подтвердил зелёные матричные Analyze/Test jobs на обеих версиях.

#### Review
Проверено по CI run `36413754181`: обе версии Flutter прошли Analyze и Test. Для 3.38.10 info остаются видимыми, но не блокируют анализ; ошибки и warnings по-прежнему блокируют.

---

### RA-06 — Гигиена CI
**Status:** DONE · **Tier:** T3 · **Owner:** Luna · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** — · **Rejection Count:** 0

#### Problem / Goal
- `android-armv7-runtime` падает в каждом run на `release/0.4.2` (11 из 11): `flutter drive` на ARM-трансляции эмулятора виснет и убивается `timeout` (exit 137). Джоба `continue-on-error`, поэтому ничего не доказывает, но красит страницу run и занимает около 25 мин.
- CI запускается на любой push, включая коммиты только в `todo.md`/`completed.md`; из последних 15 run на ветке 4 отменены из-за наложения.
- Предупреждение Node 20 для `actions/checkout@v4`.

#### Architect Decision
1. Удалить джобу `android-armv7-runtime` целиком. ARMv7 доказывается на физическом Pixel 3 (RA-25). Шаг `Verify ARMv7-only APK contents` перенести в `android-native-build` как отдельный шаг после сборки: `flutter build apk --debug --target=integration_test/native_app_runtime_smoke_test.dart --target-platform android-arm --split-per-abi` + та же проверка состава APK (сборку armv7 продолжаем проверять в CI, запуск — нет).
2. В начало workflow: `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }`.
3. В `on.push` и `on.pull_request`: `paths-ignore: ['**/*.md', 'doc/archive/**', 'doc/archive/perf/**']`. `README.md` и `CHANGELOG.md` тоже игнорируются — они проверяются финальным run RA-50.
4. Использовать `actions/checkout@v4`: репозиторий разрешает только эту версию. Обновление до `@v5` блокируется allowlist GitHub Actions. Другие actions не трогать; пока allowlist не изменён Engineer, предупреждение Node 20 для разрешённой версии документируется.

#### Constraints / Non-goals
Не менять шаги остальных джоб, кроме переноса проверки APK. Не делать другие джобы non-blocking.

#### Definition of Done
- [ ] В workflow нет `android-armv7-runtime` и нет `continue-on-error`
- [ ] Проверка состава armv7 APK выполняется в `android-native-build` и зелёная
- [ ] Коммит только в md не запускает CI (проверить пустым md-коммитом в отчёте)
- [ ] Нет ошибок allowlist для checkout; предупреждение Node 20 документировано, пока разрешён только `@v4`

#### Validation / Testing
YAML-парсинг локально; ссылка на CI-run.

#### Executor Report
Удалена джоба `android-armv7-runtime`; сборка ARMv7-only APK и проверка его ABI находятся в `android-native-build`. Добавлены отмена устаревших запусков и `paths-ignore`. `checkout@v5` блокируется allowlist репозитория, поэтому workflow использует разрешённый `@v4`; Node 20 warning остаётся видимым и не блокирует job. В CI run `36411031370` Android build и Verify ARMv7-only APK contents прошли. Markdown-only push `0ea4483` не создал новый run, что подтверждает `paths-ignore`.

#### Review
Поведение workflow и allowlist подтверждены; Android ARMv7 APK и ABI check прошли в CI. Node 20 warning принят как ограничение repo allowlist, поскольку разрешена только `checkout@v4`.

---

### RA-08 — Разблокировать `pub publish --dry-run`
**Status:** DONE · **Tier:** T3 · **Owner:** Luna · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** — · **Rejection Count:** 0

#### Problem / Goal
`wasm-web-integration` падает в каждом run на шаге `Verify published package contains committed WASM`: dry-run выходит с кодом 65 из-за предупреждения «10 checked-in files are ignored by a `.gitignore`» (логи `doc/archive/perf/results/blur0{1,2}_*/**/*.log`, коммиты `2285ca9`, `c115d78`). Из-за этого до пересборки WASM и Web-гейта джоба не доходит.

#### Architect Decision
Сырые логи — мусор, а не доказательство: 8 из 10 — дамп logcat рядом с одноимённым `.jsonl`, где лежат те же измерения; `host.log` пустой; `host-error.log` (479 байт) — ошибка неудачного запуска. Ни один md-файл на них не ссылается как на источник данных. Два кадра `*.nv12` (по 2,3 МБ) — сырой вывод BLUR-04; отчёт хранит их checksum, ссылок на файлы нет.

`git rm` (не в архив):
- `doc/archive/perf/results/blur01_raw/{yonly,yuv}/*.log`
- `doc/archive/perf/results/blur01_visual_raw/{rgb,yonly,yuv}/*.log`
- `doc/archive/perf/results/blur02_raw/{yonly,yuv}/*.log`
- `doc/archive/perf/results/blur02_control/mean_then_box/mean/*.log` (3 файла)
- `doc/archive/perf/results/blur04_raw/separable/20260926-014531-gaussian-separable.nv12`
- `doc/archive/perf/results/blur04_raw/yuv/20260926-014225-gaussian-yuv.nv12`

`.gitignore` не менять: `*.log` остаётся игнорируемым, чтобы логи больше не попадали в репозиторий. `.jsonl`/`.csv` не трогать.

#### Constraints / Non-goals
Не удалять `.jsonl`, `.csv`, `.md`. Не переписывать историю git.

#### Definition of Done
- [ ] В `git ls-files` нет ни одного `*.log` и `*.nv12`
- [ ] `flutter pub publish --dry-run` локально: предупреждения о gitignored-файлах нет
- [ ] В CI-run шаг `Verify published package contains committed WASM` зелёный. Следующее ожидаемое падение — `Rebuild and compare WASM artifacts` (устаревший WASM); его чинит RA-40, в этой карточке не исправлять.

#### Validation / Testing
Вывод dry-run и ссылка на run.

#### Executor Report
Удалены все 10 tracked `*.log` и 2 tracked `*.nv12`; проверка `git ls-files` по этим расширениям вывела пустой результат. `flutter pub publish --dry-run` после `30fff53` прошёл с 0 warnings (одна допустимая подсказка по версии). В CI run `36411031370` шаг `Verify published package contains committed WASM` также прошёл с 0 warnings и нашёл оба committed WASM assets; следующий rebuild step правильно обнаружил их устаревшее состояние (RA-40).

#### Review
Удаления соответствуют Architect Decision; `.jsonl`/`.csv` и `.gitignore` не менялись. Локальный dry-run и CI package gate прошли. Публикация пакета не выполнялась.

---


### RA-02 — Чистый архив пакета
**Status:** DONE · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** RA-01, RA-08 · **Rejection Count:** 0

#### Problem / Goal
`pub publish --dry-run` возвращает exit 65: 10 tracked `*.log` игнорируются `.gitignore`. Корневой `.pubignore` заменяет корневой `.gitignore`, поэтому всё не перечисленное в `.pubignore` публикуется.

#### Architect Decision
- Tracked `*.log` удалены в RA-08; проверить, что `git ls-files` по-прежнему не содержит файлов, игнорируемых `.gitignore`.
- В `.pubignore` добавить: `/doc/archive/`, `/todo*.md`, `/pre-release-todo.md`, `/completed.md`, `/scratch_rt_check/`, `/test/tmp_verify/`, `/test/probe/baseline/`; сохранить существующие строки.
- Allowlist верхнего уровня архива: `CHANGELOG.md`, `LICENSE`, `README.md`, `CMakeLists.txt`, `analysis_options.yaml`, `ffigen.yaml`, `pubspec.yaml`, `android/`, `assets/`, `example/`, `ios/`, `lib/`, `linux/`, `macos/`, `src/`, `test/`, `test_native/`, `tool/` (только `verify_bindings_audit.dart`, `reference/`, `wasm/build_wasm.sh`, `wasm/README.md`, `abi_v1_wasm_harness.cjs`), `windows/`.

#### Definition of Done
- [x] `flutter pub publish --dry-run` — 0 warnings (hint о скачке версии от 0.2.4 допустим)
- [x] Дерево в выводе совпадает с allowlist; в отчёте — итоговый размер архива
- [x] `yuv_ffi.js` и `yuv_ffi.wasm` присутствуют в выводе

#### Validation / Testing
Вывод dry-run приложить к отчёту (дерево верхнего уровня + итоговая строка размера).

#### Executor Report
После добавления `/dart_test.yaml` в `.pubignore` dry-run на чистом коммите `e66751e` завершился с кодом 0: 0 warnings, 1 допустимая hint о скачке версии с 0.2.4; сжатый архив — 974 KB. Верхний уровень точно совпал с allowlist RA-02; `dart_test.yaml`, архивы и `tool/bench/` отсутствуют. В дереве есть `assets/wasm/yuv_ffi.js` и `yuv_ffi.wasm`. Файлы `*.log` и `*.nv12` отсутствуют в `git ls-files`.

#### Review
Проверены полный dry-run log и список верхнего уровня; публикация не выполнялась.

---

### RA-04 — Переименовать тесты с номерами задач
**Status:** DONE · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** RA-01, RA-05, RA-06 · **Rejection Count:** 0

#### Architect Decision
`git mv`:
- `test/bgra03_dest_alloc_test.dart` → `test/convert_destination_allocation_test.dart`
- `test/bgra04_copy_out_test.dart` → `test/convert_copy_out_test.dart`
- `test/opt14_copy_contract_test.dart` → `test/plane_row_copy_contract_test.dart`
- `test/rel05_independent_results_test.dart` → `test/independent_results_test.dart`
- `test/web/rel05_independent_results_web_test.dart` → `test/web/independent_results_web_test.dart`
- `test/rel06_deprecated_api_test.dart` → `test/deprecated_api_test.dart`
- `test/rel06_public_surface_test.dart` → `test/public_surface_test.dart`
- `test/rel20_encode_decode_test.dart` → `test/encode_decode_test.dart`
- `example/integration_test/rel02_rel05_web_regression_test.dart` → `example/integration_test/web_ownership_regression_test.dart`
- `example/integration_test/yuv40_web_matrix_abort_test.dart` → `example/integration_test/web_matrix_abort_test.dart`

Обновить все упоминания путей в `.github/workflows/ci.yml` и README.

#### Constraints / Non-goals
Содержимое тестов не меняется (описания чистит RA-14).

#### Definition of Done
- [x] Все 10 файлов переименованы; старых имён нет ни в CI, ни в README
- [x] `flutter analyze lib test` — чисто; локально 703 теста; в CI run `36415310682` прошли все jobs, кроме WASM rebuild gate RA-40, который останавливает Web job до интеграционных целей.

#### Validation / Testing
`flutter analyze lib test`; `flutter test` — количество тестов не уменьшилось (сравнить со значением до правки).

#### Executor Report
Переименованы 10 тестовых файлов и обновлены пути в CI/README. `flutter analyze lib test` чистый, `flutter test` прошёл 703 теста. В run `36415310682` все jobs прошли, кроме `wasm-web-integration`, где сравнение пересобранных WASM assets остановилось до Web integration целей; причина зарегистрирована в RA-40 и не связана с переименованием.

#### Review
Старые имена не найдены в CI и README; новые файлы существуют. Анализ и число тестов подтверждены локально. CI подтверждает остальные платформенные jobs; Web target names требуют повторной проверки после RA-40.

---





### RA-16 — Комментарии example
**Status:** DONE · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** RA-01, RA-04 · **Rejection Count:** 0

**Scope:** `example/lib/**`, `example/test/**`, `example/integration_test/**` (кроме архивированного), `example/pubspec.yaml` (комментарии), `example/README.md`.
**Architect Decision:** DOC-RULES. `example/README.md` — короткое описание: что показывает пример, как запустить на каждой платформе, какие разрешения камеры нужны.
**Validation:** `cd example && flutter analyze && flutter test`.

#### Executor Report
README описывает запуск для настроенных Android, iOS, macOS, Windows и Web runners, доступ к камере и необходимые разрешения; Web указан как partial WASM backend. Удалены служебные номера задач из комментариев example README, pubspec, benchmark/camera helpers и Web integration tests.

`cd example && flutter analyze` — чисто; `flutter test` — 71 тест прошёл. Dart format сообщил 0 изменённых файлов. Проверка DOC-RULES оставляет только runtime строки для CI (`YUV-12`, `YUV-40`, `YUV-06`) и технические имена до перехода состояния (`pre-screen`, `pre-injection`); не переписывал их как текст сообщений или терминов.

#### Review
Проверено: изменения ограничены текстом документации, комментариями и описаниями тестов; логика приложения не менялась. Analyze, 71 тест и форматирование выполнены после правки.

---
