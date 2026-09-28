# yuv_ffi 0.4.2 — предрелизный цикл RA

Источник: предрелизный аудит 27.09.2026 (HEAD `9b41cb5`), повторная сверка 28.09.2026 на `db42681`. Карточки RA заменяют PRE-00…07 из `doc/archive/perf/prerelease-todo.md`. Архитектор — Claude Opus (T1). Готовность карточки не означает разрешения: запуск — только по команде Engineer, по ID или пакету.

**Объём релиза заморожен.** VIEW-00…03 и PACK-00…01D приняты. С начала цикла RA в `lib/`, `src/`, `example/lib/` не добавляется новая функциональность; любое новое требование — отдельной карточкой после решения Engineer.

## CI runner policy

Engineer установил правило: jobs проекта не должны выполняться на GitHub-hosted runners; исключение — один Linux job. GitHub API на 28.09.2026 показывает онлайн `dev.working` (`Windows`, `X64`) и `yuv-self-hosted` (`macOS`, `X64`). Linux job `linux-native-smoke` объединяет Linux packaging/runtime smoke и native sanitizer suite; это единственная job, оставленная на GitHub-hosted `ubuntu-latest`. Остальные jobs используют self-hosted runners. WSL не устанавливался: Windows runner нужен для Android и Web/WASM, а пользователь указал, что WSL/Hyper-V может затронуть режим гибернации; менять системную конфигурацию нельзя без его решения.

Текущая маршрутизация: macOS native, iOS Simulator и bindings regeneration — `yuv-self-hosted`; Windows native, Flutter VM matrix, Android x86_64 emulator, Web/WASM и example analyze/build — `dev.working`; Linux smoke плюс sanitizer — единственная hosted Linux job. На Windows runner доступны Android SDK `D:\.important\android-sdk`, x86_64 API 35 AVD `Tablet` (конфигурация `Pixel_Tablet.avd`), Chrome `154.0.8037.58`, ChromeDriver `D:\.projects\.tools\chromedriver-win64\chromedriver.exe` (`154.0.8037.57`) и Git Bash `D:\.important\Git\bin\bash.exe`. Установленный глобально emsdk `5.0.1` не используется для RA-40; runner ставит точный `3.1.74` в `D:\.projects\.tools\emsdk-3.1.74`.

**Состояние на 28.09.2026, commit `8af210e` плюс текущая рабочая копия:** RA-05 ранее прошёл на Flutter 3.38.10 и 3.44.9 в run `36413754181`. RA-02 dry-run: 0 warnings, allowlist соблюдён, архив 974 KB; публикации не было. В run `36427394808` прошли Linux smoke/sanitizer, macOS native smoke, iOS simulator/device build и smoke, bindings regeneration и example analyze/build 3.41.0. Windows root tests выявили две runner-specific проблемы: test provenance не искал DLL в PATH; probe source/copy различались только CRLF/LF. В рабочей копии исправлен Windows PATH lookup, добавлен `.gitattributes` LF для synced probe-файлов; локально `flutter analyze --no-fatal-infos lib test` чистый, полный `flutter test` прошёл 703 теста с собранной DLL в PATH. Commit и CI rerun ожидаются. Android job в `36427394808` ещё не стартовал; предыдущий run собрал arm64/armv7 APK, а новое имя API 35 x86_64 AVD `Tablet` ждёт подтверждения CI. RA-21 oracle совпал на 1188/1188 случаях и локальный Windows probe прошёл; требуется финальное независимое ревью. На свежих emsdk 3.1.74 assets Web probe завершился exit 1 с минимум 20 gray I420/NV12 mismatches (доказательство в `doc/archive/release-0.4.2/web-probe-evidence.md`); RA-41 требует решения Architect. Pixel 3 profile smoke и probe 1188/1188 прошли, APK arm64/armv7 собраны; release assertions остаются заблокированы ограничением Flutter Driver, см. RA-25. Runner API показывает `dev.working` (Windows x64) и `yuv-self-hosted` (macOS x64) online. Только Linux smoke/sanitizer job использует GitHub-hosted runner; Android, Web и Windows jobs — self-hosted Windows, iOS/macOS/bindings — self-hosted Mac.

## Решения Engineer

| ID | Status | Вопрос | Рекомендация Architect |
| --- | --- | --- | --- |
| D-1 | DECIDED 28.09.2026 | Версия релиза при смене умолчания layout (PACK-01B). | **0.4.2.** Последняя опубликованная неотозванная версия — 0.2.4, 0.4.0 отозвана, поэтому 0.5.0 ничего не даёт. Смена умолчания описывается как **Behavior change** в CHANGELOG и отдельной строкой в таблице миграции с 0.2.4 в README: фабрики с `planes:` теперь упаковывают плоскости, для старого поведения — `layout: YuvPlaneLayout.preserve`. |

| Done | ID | Status | Tier | Owner | Depends On | Summary |
| --- | --- | --- | --- | --- | --- | --- |
| [x] | RA-05 | DONE | T3 | Luna | — | Обе матричные Analyze/Test jobs прошли на Flutter 3.38.10 и 3.44.9 (run `36413754181`); legacy info остались видимыми, но не блокируют. |
| [x] | RA-06 | DONE | T3 | Luna | — | Гигиена CI подтверждена: checkout использует разрешённую `@v4`, ARMv7 APK build и проверка ABI зелёные, Markdown-only push не запускает workflow. Предупреждение Node 20 остаётся, так как allowlist блокирует `@v5`. |
| [x] | RA-08 | DONE | T3 | Luna | — | Удалены 10 сырых `*.log` и 2 `*.nv12`; CI dry-run проверка package assets прошла с 0 warnings. |
| [x] | RA-02 | DONE | T3 | — | RA-01, RA-08 | Dry-run на `e66751e`: 0 warnings, 1 допустимая hint, allowlist совпал, архив 974 KB; публикации в pub.dev нет. |
| [x] | RA-04 | DONE | T3 | — | RA-01, RA-05, RA-06 | 10 файлов переименованы; analyze чистый, 703 теста прошли; run `36415310682` прошёл во всех jobs, кроме независимого WASM rebuild gate RA-40. |
| [ ] | RA-14 | TODO | T3 | — | RA-04 | Вычистить комментарии и описания `group`/`test` в `test/` по DOC-RULES. Логика тестов не меняется. |
| [x] | RA-16 | DONE | T3 | — | RA-01, RA-04 | README и example-комментарии очищены по DOC-RULES; `flutter analyze` чистый, 71 example test пройден. Сохранены только CI runtime markers/messages и термины `pre-screen`/`pre-injection`, описывающие состояние. |
| [ ] | RA-19 | TODO | T3 | — | RA-22, RA-23, RA-41 | Вычистить служебные README (`tool/wasm`, `assets/wasm`, `test_native`) и комментарии CI от номеров задач. |
| [ ] | RA-21 | IN_PROGRESS | T2 | — | — | Локальные DoD пройдены: 1188 оракулов/проб на Windows, 703 root tests, coverage/layout/copy sync. Ожидает финального независимого ревью; Web runtime mismatches на пересобранном WASM вынесены в RA-41. |
| [ ] | RA-26 | TODO | T2 | — | RA-21 | Добавить в пробы замер скорости: общий исполнитель, методика, контроль окружения, строка вердикта и JSON; базовые линии Windows и Pixel 3 от 0.4.0 и HEAD. |
| [ ] | RA-27 | TODO | T3 | — | RA-26 | Записать в AGENTS.md правило проб для задач разработки (Windows у исполнителя, Pixel 3 на ревью) и поле `Probe` в шаблон карточки. |
| [ ] | RA-22 | TODO | T2 | — | RA-04, RA-06, RA-21 | Подключить пробу корректности в CI для Linux, macOS, iOS Simulator, Android x86_64 перебором `*_native_test.dart` и общим скриптом вердикта `tool/ci/drive.sh`. |
| [ ] | RA-23 | IN_PROGRESS | T2 | — | RA-06, RA-21, RA-22 | Windows job настроена на native build, полный `flutter test`, Windows build, runtime smoke и correctness probe. Run `36427394808` подтвердил Git Bash/CMake PATH, но root tests выявили Windows DLL provenance lookup и CRLF/LF sync; оба исправлены локально, `flutter test` — 703/703 с DLL в PATH. Новый CI run должен подтвердить fixes и AVD `Tablet`. |
| [ ] | RA-25 | IN_PROGRESS | T2 | — | RA-13, RA-21, RA-26 | Pixel 3 доступен через ADB. Profile smoke и probe 1188/1188 прошли; release APK arm64/armv7 собраны, arm64 установлен и запущен. Требуемый `flutter drive --release` не поддержан Flutter Driver и завершился до сборки; профильный прогон не заменяет release assertions. Ожидает решения/реализации release smoke, RA-26 замеры. Доказательство: `doc/archive/release-0.4.2/pixel3-evidence.md`. |
| [ ] | RA-40 | IN_PROGRESS | T2 | — | RA-06, RA-08, RA-13 | Assets пересобраны на Windows через изолированный emsdk 3.1.74; повторная сборка совпала побайтно. CI compare ещё не запускался: Windows runner сначала остановился на Setup Flutter, затем на native build из-за отсутствия CMake в PATH; проверка ожидает повторного run после PATH fix. |
| [ ] | RA-41 | ARCHITECT_REQUIRED | T2 | — | RA-04, RA-21, RA-22, RA-40 | ChromeDriver 154 запустил 1188-case Web probe на пересобранных assets; зафиксированы как минимум 20 golden mismatches серых I420/NV12 операций. Нужна позиция Architect по эталонному результату. |
| [ ] | RA-18 | TODO | T2 | — | все RA кроме RA-50 | Финальный CHANGELOG 0.4.2 вместо черновика: фактические изменения, новый API, известные ограничения. |
| [ ] | RA-50 | TODO | T2 | — | все RA | Не начат: ждёт закрытия предыдущих RA и финального CI на одном SHA. Тег и публикация — Engineer; pub.dev publish не входит в эту работу. |

Дополнение к разбиению от 28.09.2026: RA-10, RA-11, RA-12, RA-13, RA-15 и RA-17 выполняются параллельно с RA-01. Их области — Dart/C комментарии, test_native комментарии и README; RA-01 перемещает файлы, меняет ссылки в orchestration Markdown и одну ссылку в CHANGELOG. Пересечений по изменяемым строкам нет. Валидация каждой карточки остаётся обязательной. RA-16 остаётся после RA-01 и RA-04 из-за пересечения с перемещаемыми example integration tests. После группы продолжаем по зависимостям таблицы.

Ревью: T3 → T2; T2 → T1 (предпочтительно другой провайдер, чем исполнитель); RA-50 — T1 + Engineer. Принятые карточки переносятся в `COMPLETION.md` по протоколу; этот файл содержит только текущую работу цикла.

---

## DOC-RULES — общее решение Architect для RA-10…RA-19

1. Удалить: номера задач и ревью (`YUV-`, `REL-`, `BGRA-`, `AUD-`, `OPT-`, `BLUR-`, `CVT-`, `VIEW-`, `MEAS-`, `PERF-`, `PRE-`, `WAIT-`, `PATCH-`, `F-0xx`), ссылки на `todo*.md`, `COMPLETION.md`, `completed.md`, `doc/perf`, `doc/archive`, `doc/archive/api-abi-0.4-design.md`, «section N», «Q1», пересказ истории («used to», «earlier revisions», «pre-…», «was removed in …», «independent review showed»).
2. Оставить и при необходимости переформулировать: что делает символ, параметры, возврат, исключения, побочные эффекты (revision, мутация, владение памятью), платформенные различия, ограничения, неочевидное «почему» — без ссылки на задачу.
3. Публичный dartdoc — по Effective Dart: первая фраза — краткое описание; `Throws …` для документированных ошибок; ссылки `[Symbol]` только на экспортируемые символы.
4. Комментарий, который после чистки ничего не объясняет, удаляется целиком. Бесполезные `// ignore:` внутри dartdoc-блоков удаляются только если анализ остаётся чистым.
5. Код, сигнатуры, строки сообщений об ошибках, имена символов не меняются. Если комментарий противоречит коду — код не трогать, записать расхождение в Executor Report (ARCHITECT_REQUIRED, если это меняет контракт).
6. Язык комментариев — английский (как сейчас в коде).

Проверка для каждой DOC-задачи: регэксп из п.1 по файлам scope даёт 0 совпадений (исключения перечислить в отчёте с причиной); `git diff` содержит только строки комментариев.

---

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





### RA-14 — Комментарии и описания тестов `test/`
**Status:** TODO · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** RA-04 · **Rejection Count:** 0

**Scope:** `test/**/*.dart`.
**Architect Decision:** DOC-RULES, плюс строки описаний `group(...)`/`test(...)`: убрать префиксы-номера `(YUV-36d)` и т.п., оставить описание поведения. Уникальность описаний внутри файла сохраняется.
**Constraints:** логика, ожидания, фикстуры не меняются.
**DoD:** регэксп = 0; количество тестов в `flutter test` не изменилось.
**Validation:** `flutter analyze lib test`; `flutter test`.

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


### RA-19 — Служебные README и комментарии CI
**Status:** TODO · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** RA-22, RA-23, RA-41 · **Rejection Count:** 0

**Scope:** `tool/wasm/README.md`, `assets/wasm/README.md`, `test_native/README.md`, комментарии `.github/workflows/ci.yml`.
**Architect Decision:** DOC-RULES; в `ci.yml` менять только строки `#`.
**Validation:** `actionlint` при наличии, иначе YAML-парсинг (`python -c "import yaml,sys;yaml.safe_load(open(sys.argv[1]))" .github/workflows/ci.yml`).

---

### RA-21 — Пробы: корректность (golden-хэши)
**Status:** IN_PROGRESS · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** — · **Rejection Count:** 0

#### Problem / Goal
Полный поведенческий набор запускается только на Linux x64 VM (CI) и Windows локально. На Android/iOS/macOS/Linux-app проверяется только smoke 4×4 («не нули»). 44 из 119 референсных случаев сравниваются с допуском, поэтому дрейф переписанных ядер может пройти незамеченным.

#### Architect Decision
- Матрица: форматы I420/NV12/BGRA8888 × размеры 1×1, 2×2, 3×5, 16×9, 33×17, 127×255 × раскладки `tight`, `padded` (+7 байт к rowStride), `gap` (I420 pixelStride 2 для Y и UV, NV12 UV pixelStride 3, BGRA pixelStride 5) × 22 операции: grayscale, blackWhite, negate, gaussian(r3, σ2), box(r2), mean(r2), box c ROI, mean c ROI, crop со смещением 1, crop по чётной границе, cropped, flipH, flipV, rotation 90/180/270, toI420, toNv12, toBgra, toBgraBytes, applyRgbaBytes, chromaSwap (только NV12) — всего 1188 случаев. Вход детерминирован LCG. Исходник матрицы — архитектурный харнесс [`doc/archive/audit-2026-09-27/regress_dump_seed.dart`](doc/archive/audit-2026-09-27/regress_dump_seed.dart): форматы, размеры, раскладки, операции, LCG (`_seed = 12345 + width * 31 + height`, пересчёт перед каждым случаем) и формат id `<format> <W>x<H> <layout> <op>` переносить из него без изменений. Оракул 0.4.0 — [`regress_dump_v040.txt`](doc/archive/audit-2026-09-27/regress_dump_v040.txt), 1188 строк.
- **Layout после PACK-01B:** фабрики по умолчанию упаковывают переданные плоскости. Случаи `padded` и `gap` создают образ с `layout: YuvPlaneLayout.preserve`, иначе они молча превратятся в `tight`. Отдельная группа случаев проверяет умолчание `.packed` и `pack()`: для каждой раскладки хэш `toBgraBytes()` до и после упаковки совпадает, `isTightlyPacked` после `pack()` — `true`.
- Результат случая — строка ровно в формате харнесса: для `YuvImage` — `<format> <W>x<H> <sha16(toBytes)> src=<sha16(toBytes источника)>`, для `Uint8List` — `<sha16>`, для ошибки — `ERR <runtimeType>`. Строка оракула — это id до `: ` и значение после. В `golden.json` значения матрицы хранятся в том же виде, поэтому сравнение с оракулом — простое равенство строк.
- **Раскладка файлов (одна операция — один файл, без центрального реестра логики):**
  - `test/probe/cases/<operation>.dart` — только данные случаев операции;
  - `test/probe/cases.dart` — список файлов операций, одна строка на операцию;
  - `test/probe/golden.json` — `{"schema":1,"cases":{"<id>":"<hash>"}}`;
  - `test/probe/probe_correctness_test.dart` с `@Tags(['probe'])` — не пропускается при отсутствии native, а падает;
  - `test/probe/operation_coverage_test.dart` — у каждого значения `YuvOperation.values` есть файл случаев; новая операция без случаев = красный тест.
- **Golden только дополняется.** Режим записи `PROBE_RECORD=1` дописывает отсутствующие id; перезапись существующего id — только с `PROBE_RECORD=overwrite` и отметкой в отчёте как изменение поведения. Новый случай без эталона — тест падает с сообщением «нет эталона».
- Golden записывается на Windows x64 от HEAD. Эквивалентность с 0.4.0 доказывается сравнением с оракулом `regress_dump_v040.txt`: для каждого из 1188 случаев матрицы хэш в `golden.json` равен хэшу оракула (0 расхождений). Сборка 0.4.0 не нужна. Случаи группы `pack()`/`layout` в оракуле отсутствуют и в сравнение не входят. Сравнение везде точное.
- Архитектор проверил 28.09.2026: харнесс на HEAD `fda3215` (native собран MSVC Release) с `layout: YuvPlaneLayout.preserve` даёт дамп, побайтно равный оракулу (SHA-256 файла `69BE886405F75E50…`, 0 расхождений из 1188, 0 ошибок). Если у исполнителя расхождение — это дефект порта харнесса, а не повод обновить golden.
- `dart_test.yaml` в корне: теги `probe` и `release`; `release` исключён по умолчанию.
- Example: `example/integration_test/probe_native_test.dart` (все native-платформы) и `probe_web_test.dart` (WASM) + копии `test/probe/**` в `example/integration_test/helpers/probe/` и `golden.json` в `example/assets/probe/`; копирование — расширить `example/tool/copy_reference_fixtures.sh`; `test/probe/probe_copy_sync_test.dart` проверяет побайтное совпадение копий.
- Расхождение golden на какой-либо платформе не ослабляется допуском: исполнитель RA-22/23/25/41 переводит карточку в ARCHITECT_REQUIRED с перечнем случаев.

#### Constraints / Non-goals
Не менять `lib/`, `src/`. Не заменять существующий референс 119 случаев. Замер скорости — RA-26, здесь только корректность.

#### Definition of Done
- [ ] ≥ 1188 случаев матрицы + группа `pack()`/`layout`; в golden ≥ 900 различных хэшей (чувствительность)
- [ ] Доказано 0 расхождений с 0.4.0 на общих случаях (лог в отчёт)
- [ ] `operation_coverage_test` зелёный; удаление любого файла случаев делает его красным (негативный контроль в отчёте)
- [ ] Негативный контроль: изменение одного хэша в golden валит тест
- [ ] VM-тест и example-цель проходят на Windows локально (`flutter drive -d windows`)

#### Validation / Testing
`flutter test --tags probe`; `flutter test test/probe/probe_copy_sync_test.dart`; `cd example && flutter drive --driver=test_driver/integration_test.dart --target=integration_test/probe_native_test.dart -d windows`.

#### Executor Report
Восстановленный seed harness выдал 1188/1188 строк, идентичных сохранённому 0.4.0 oracle. Созданы 22 отдельных файла с данными операций, golden с 1188 случаями и 949 уникальными результатами, проверка покрытия 12 значений `YuvOperation`, синхронизация копий и layout/pack suite на 54 сочетаниях. `flutter test --tags probe`, copy-sync/coverage/layout suite, analyze и Windows `flutter drive` прошли; Windows log подтвердил 1188 случаев. Web target добавлен; локальный запуск требует ChromeDriver на порту 4444, браузерный gate остаётся RA-41.

#### Review
Ожидает финального независимого ревью.

---

### RA-26 — Пробы: замер скорости
**Status:** TODO · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** RA-21 · **Rejection Count:** 0

#### Problem / Goal
Агент должен одной командой узнать по каждой операции: корректна ли она, стала ли быстрее или медленнее. Регрессия 0.4 (ядра в 10–350 раз медленнее 0.2.4) была замечена только по жалобе.

#### Architect Decision
- Файлы операций RA-21 (`test/probe/cases/<operation>.dart`) дополняются необязательными сценариями замера. Общий исполнитель `test/probe/probe_runner.dart` — только цикл: прогрев, N замеров, медиана и разброс, сравнение с базой. Логики операций в нём нет.
- Вход — общий детерминированный кадр: `test_pattern_512.png`, растянутый ближайшим соседом до нужного размера в коде (без новых больших ассетов), либо LCG для раскладок. Одно определение входа для VM и устройства.
- Размеры для замера: 1920×1080 и 720×360. Замеряется полный публичный вызов.
- Вердикт в строке `PROBE <op> <scenario> <size> PASS|FAIL <median> ms (baseline <x>, ±<p>%) FASTER|SAME|SLOWER|NO-BASELINE` и в `probe-result.json`.
  - `SLOWER`, если медиана хуже базы больше чем на max(15%, 2 × разброс);
  - `FASTER` — симметрично;
  - несовпадение хэша — всегда FAIL (красный тест);
  - `SLOWER` краснеет только при `PROBE_STRICT=1`; в CI скорость только пишется в отчёт.
- База: `test/probe/baseline/<host-id>.json`, где `<host-id>` = ОС, модель CPU/устройства, ABI, режим сборки. Обновление только через `PROBE_RECORD=1`.
- Контроль окружения (иначе замер помечается `INVALID-ENV`):
  - Windows — питание от сети, схема питания «Высокая производительность»;
  - Pixel 3 — `mWakefulness=Awake`, экран включён, keyguard снят, нет thermal throttling (`dumpsys thermalservice`), пауза остывания между операциями.
- Команды:
  - Windows: `flutter test --tags probe` в Release-сборке native; Dart в JIT честно помечается в отчёте.
  - Pixel 3: `tool/probe/run_android.ps1 [-Ops convert,crop] [-Abi arm64|armv7]` — `flutter drive --profile` цели `integration_test/probe_native_test.dart`.

#### Definition of Done
- [ ] Сценарии замера для всех 12 `YuvOperation`
- [ ] Базовые линии Windows x64 и Pixel 3 arm64 сняты для тега 0.4.0 и для HEAD; таблица сравнения — в отчёте (источник цифр для CHANGELOG RA-18)
- [ ] Негативный контроль: искусственное замедление (sleep в тестовой сборке исполнителя, не в `lib/`) даёт `SLOWER`, испорченный golden даёт FAIL
- [ ] Два повторных прогона на одной машине дают `SAME`

---

### RA-27 — Правило проб в AGENTS.md
**Status:** TODO · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** RA-26 · **Rejection Count:** 0

#### Architect Decision
Добавить в `AGENTS.md` проекта раздел «Probes»:
- В карточке задачи поле `Probe: none | windows | windows+pixel3`. Правка `src/` или `lib/src/yuv/impl/**`, а также любая заявка о скорости → `windows+pixel3`; прочие правки `lib/` → `windows`; документация и CI → `none`.
- Исполнитель прогоняет пробу на Windows и прикладывает строки вердикта к отчёту. FAIL — задача не сдаётся. `SLOWER` — объяснить или исправить.
- Ревьюер прогоняет пробу на Pixel 3 (arm64; при правке `src/` — ещё и armv7). Задача принимается, только если обе пробы PASS и нет необъяснённого `SLOWER`.
- Базу обновляет не исполнитель, а ревьюер после приёмки, отдельным коммитом с причиной.
- Остальные платформы: корректность проверяется в CI на каждом push, скорость — на предрелизной проверке.

#### Definition of Done
- [ ] Раздел добавлен
- [ ] Шаблон карточки (в `todo.md`) содержит поле `Probe`

---

### RA-22 — Проба корректности в платформенных CI-джобах
**Status:** TODO · **Tier:** T2 · **Execution Mode:** FAST · **Review Tier:** T1 · **Depends On:** RA-04, RA-06, RA-21 · **Rejection Count:** 0

**Architect Decision:** в `linux-native-smoke`, `macos-native-smoke`, `ios-native-build`, `android-native-build` после шага app-runtime smoke добавить шаг, который перебирает `integration_test/*_native_test.dart` (сейчас это `probe_native_test.dart`) на том же устройстве; новая цель с таким суффиксом попадает во все джобы без правки YAML (джоба `android-armv7-runtime` удалена в RA-06; ARMv7 доказывается RA-25). Вердикт выносит общий `tool/ci/drive.sh <target> <device>`: PASS только при exit 0 **и** строке `All tests passed` в выводе; скрипт используют все джобы с `flutter drive`, включая app-runtime smoke.
**DoD:** зелёный CI-run на ветке; в логах каждой из 4 джоб видно выполнение 1188 случаев.
**Validation:** ссылка на run; негативный контроль — один прогон с испорченным golden в отдельном коммите, который красит джобы, затем откатывается.

---

### RA-23 — Windows CI
**Status:** TODO · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** RA-06, RA-21, RA-22 · **Rejection Count:** 0

**Architect Decision:** новая джоба `windows-native-smoke` на `windows-latest`, Flutter 3.44.9: `cmake -S src -B $RUNNER_TEMP/nb -A x64` + Release; каталог сборки добавить в `PATH`; `flutter test` (полный набор, без пропусков native); `cd example && flutter build windows --release`; `flutter drive -d windows` для `native_app_runtime_smoke_test.dart` и всех `*_native_test.dart` через `tool/ci/drive.sh`. Блокирующая.
**DoD:** зелёный run; в логе `flutter test` нет пропущенных native-тестов.

---

### RA-25 — Физический Pixel 3: arm64 и armv7
**Status:** IN_PROGRESS · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** RA-13, RA-21, RA-26 · **Rejection Count:** 0

**Architect Decision:** на Pixel 3 (экран включён, keyguard снят — проверить `dumpsys power`) выполнить в `--release`: `native_app_runtime_smoke_test.dart` и `probe_native_test.dart`; в `--profile` — замер скорости RA-26 (`tool/probe/run_android.ps1`), базой служит HEAD, принятый в RA-26, для (а) обычной сборки arm64-v8a и (б) APK `--target-platform android-arm --split-per-abi` с проверкой состава APK как в CI-джобе armv7. Доказательство (SHA, модель, Android, ABI, полный вывод) — `doc/archive/release-0.4.2/pixel3-evidence.md`.
**DoD:** оба прогона — `All tests passed`; файл доказательства закоммичен.
**Constraints:** это единственный gate для ARMv7 и arm64 Android (CI-джоба armv7 удалена в RA-06).

#### Executor Report
Pixel 3 (`8B1X11QLW`, Android 12, `arm64-v8a,armeabi-v7a,armeabi`) подключён через ADB; экран включён, keyguard снят, thermal status 0. Profile app-runtime smoke и native probe завершились `All tests passed`; probe обработал 1188 случаев. Release APK arm64 и armv7 собраны, в каждой APK подтверждена только целевая ABI и `libyuv_ffi.so`; arm64 APK установлена и запущена без ошибок загрузки библиотеки.

Требуемый `flutter drive --release` прекращается до сборки сообщением, что Flutter Driver не поддерживает release mode. Profile-прогон не подтверждает release assertions, а запуск основного example app подтверждает только открытие приложения. RA-25 не завершена, пока release checks не получат поддерживаемый механизм либо Engineer/Architect не изменит критерий. RA-26 performance measurements также не выполнены. Полные команды и вывод: `doc/archive/release-0.4.2/pixel3-evidence.md`.

---

### RA-40 — Пересборка WASM
**Status:** IN_PROGRESS · **Tier:** T2 · **Execution Mode:** FAST · **Review Tier:** T1 · **Depends On:** RA-06, RA-08, RA-13 · **Rejection Count:** 0

#### Problem / Goal
`assets/wasm/*` собраны в `d447fb2`, до 14 C-коммитов; доказано, что исходники HEAD дают другой `.wasm`. CI-гейт сравнивает с пересборкой на emsdk 3.1.74 и упадёт.

#### Architect Decision
На Windows runner `dev.working` использовать изолированный emsdk 3.1.74 из `D:\.projects\.tools\emsdk-3.1.74`; локальный emsdk 5.0.1 не использовать. Пересобрать assets из checkout, подтвердить повторяемость и включить их в commit. CI job сравнивает committed assets с чистой повторной сборкой на том же runner. GitHub-hosted `upload-artifact` не требуется: по решению Engineer только единый Linux smoke/sanitizer job остаётся hosted, а Web/WASM проверяется на Windows self-hosted.
**DoD:** следующий run: шаг сравнения зелёный; `git log -1 -- assets/wasm` новее последнего коммита в `src/`.

---

### RA-41 — Зелёный Web-гейт
**Status:** ARCHITECT_REQUIRED · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** RA-04, RA-21, RA-22, RA-40 · **Rejection Count:** 0

**Architect Decision:** заменить явный список целей `Required Web integration gate` перебором `integration_test/*_web_test.dart` (включая `probe_web_test.dart`; существующие web-цели из списка переименовать в этот суффикс в этой же карточке); обновить имена целей после RA-04. В цикле и в шаге матрицы 119 вердикт PASS — только при exit 0 **и** строке `All tests passed` в выводе через `tool/ci/drive.sh` из RA-22. Если golden расходится на WASM — ARCHITECT_REQUIRED со списком случаев (не ослаблять).
**DoD:** зелёная джоба `wasm-web-integration`; негативный контроль (обнуление первых 64 байт `yuv_ffi.wasm` во временном коммите) красит гейт, затем откат.

**Локальный Windows Web-run:** ChromeDriver находится в `D:\.projects\.tools\chromedriver-win64\chromedriver.exe` (154.0.8037.57), установленный Chrome — 154.0.8037.58. Запустить `chromedriver --port=4444`, затем из `example/`: `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/probe_web_test.dart -d web-server --browser-name=chrome --headless`. Эта запись хранится в `pre-release-todo.md`, исключённом из pub archive правилом `/pre-release-todo.md` в `.pubignore`.

**Текущий результат:** driver/browser подключились; после пересборки assets через emsdk 3.1.74 тест исполнил матрицу и завершился с exit 1. Подтверждено как минимум 20 mismatches: серые операции I420 для tight/padded/gap на размерах 1x1, 2x2, 3x5, 16x9, 33x17, 127x255, а также NV12 1x1 tight/padded. Сообщение теста ограничено первыми 20 случаями; вывод и команды записаны в `doc/archive/release-0.4.2/web-probe-evidence.md`. Golden не ослаблять. Нужны разбор этих случаев и решение Architect о правильном результате; до этого зелёный Web-гейт и RA-50 заблокированы. Локальный прогон не заменяет CI-гейт и его негативный контроль.

---

### RA-18 — Финальный CHANGELOG 0.4.2
**Status:** TODO · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** все RA кроме RA-50 · **Rejection Count:** 0

**Architect Decision:** убрать «draft; not published» и фразу о незавершённом рефакторинге. Разделы: Highlights; Performance (ускорение native-ядер и Dart-копирования; цифры — только измеренные, с платформой и размером; поведение побайтно совпадает с 0.4.0 по набору соответствия); Behavior change первым пунктом (умолчание `YuvPlaneLayout.packed`, решение D-1: версия остаётся 0.4.2); New API (`YuvFramePresenter`, `YuvFrameView`, `YuvPlaneLayout`, `isTightlyPacked`, `pack()`); Changes (`YuvImageProvider`: копия при старте декодирования, `StateError` для мутированного провайдера; пересобранный WASM); Documentation fixes (ROI и crop — пиксельные координаты; `copy(blank: true)` сохраняет strides; `initialize()` обязателен на IO для `apply*`); Example; Known limitations; Moving from a 0.4.0 lockfile. Без номеров задач. Держать версию в синхронизации с `pubspec.yaml`.

---

### RA-50 — Финальный релизный гейт
**Status:** TODO · **Tier:** T2 · **Execution Mode:** FAST · **Review Tier:** T1 + Engineer · **Depends On:** все RA · **Rejection Count:** 0

**DoD:**
- [ ] Один финальный SHA; на нём зелёные **все** CI-джобы (non-blocking джоб в workflow нет)
- [ ] `flutter pub publish --dry-run` — 0 warnings; дерево по allowlist RA-02
- [ ] Версия 0.4.2 совпадает в `pubspec.yaml`, `CHANGELOG.md`, `ios|macos/*.podspec`, `src/CMakeLists.txt`
- [ ] Плейсхолдеры README заменены ссылками на run финального SHA и на доказательство RA-25
- [ ] Отчёт: список run, известные ограничения, что проверено вручную
**Constraints:** не создавать тег и не публиковать — это Engineer.
