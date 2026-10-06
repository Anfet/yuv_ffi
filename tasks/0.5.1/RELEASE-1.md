# RELEASE 1 — Релизный гейт 0.5.1
**Status:** IN_PROGRESS · **Tier:** T2, Reviewer T1 + Engineer · **Owner:** Executor · **Depends On:** — · **Probe:** windows+pixel3+web

**Base SHA:** `09f18920635105c6817d895008f7f2599e82017f` (dev на старте повторного гейта)

**Release candidate:** прежний — `release/0.5.1` at `61da2ee3457ee81e1ab7de99bbf54d3170f1fde1`; новый после FIX 1 ещё не сформирован.

**Следующий шаг:** FIX 1 принята; Executor формирует новый кандидат по A1 (коммит документов `de5a5df`)
либо A2 после решения Engineer → гейт нового SHA → решение о выпуске.
Отчёты и PASS 05–06.10.2026 ниже относятся только к прежнему кандидату и не закрывают этот повторный гейт.

#### Goal

Подготовить выпуск 0.5.1: изменения относительно опубликованной 0.5.0 точно описаны в CHANGELOG, README,
MIGRATION и README примера, все проверки — на одном SHA кандидата, в репозитории нет рабочих артефактов.
Итог — отчёт Engineer, по которому он ставит тег,
публикует и переводит `main`. Тег, публикация и `main` в задачу не входят.

#### Architect Decision

1. **Аудит разницы (только чтение).** Диапазон `0.5.0..<SHA>`; результат — таблица «область → что проверено →
   находка» в Executor Report (отдельного файла аудита нет):
   - CHANGELOG `## 0.5.1` против изменений диапазона: каждое пользовательское изменение есть, внутренних пунктов нет;
   - README: «Requirements», «Platform status», «Web backend» согласованы с `doc/web-parity.md`; Safari и Firefox —
     «not verified» (D-27);
    - MIGRATION и `example/README.md` согласованы с README; interop-сбой `--wasm` обозначен как исторический для
      0.5.0, исправленный в 0.5.1; переход 0.5.0 → 0.5.1 не требует замен API/повторной миграции кадров;
   - версия `0.5.1` в четырёх файлах D-14, README и `example/pubspec.lock`;
   - публичное API не изменилось: `lib/yuv_ffi.dart` и `test/public_surface_test.dart` — без изменений или проходят;
   - следы работы в изменённых файлах `lib/`: `TODO`/`FIXME`, ID задач, `print`/`debugPrint`, новые `ignore`;
   - состав: архив dry-run — только пакет, example, `MIGRATION.md`, `assets/`; `git status --short --ignored` — без
     новых артефактов; в `tasks/0.5.1/` — только активные карточки.
   Блокирующая находка — черновик `FIX N` и `ENGINEER_REQUIRED`.
2. **Релиз-кандидат после приёмки FIX 1.** Рабочая документация меняется в `dev`; отдельный коммит четырёх документов
   берётся из `Validated at` принятой FIX 1. Новый SHA кандидата записать в `todo.md` и отчёт до проверок.
   - **A1 — действует D-31:** на `release/0.5.1` поверх прежнего кандидата перенести только этот коммит документов
     (`git cherry-pick <Validated at FIX 1>`). Пустой diff по коду, тестам, assets и CI против прежнего кандидата
     обязателен; публикационные документы должны совпасть с принятыми в FIX 1. При конфликте сверить четыре
     документа с принятым diff; если требуется иная правка содержания — вернуть FIX 1, не исправлять её в гейте.
   - **A2 — только по решению Engineer о переносе CI 2/CI 3/CI 4:** продвинуть `release/0.5.1` fast-forward до
     принятого SHA `dev` с FIX 1. Указать включённые исправления тестов/CI; гейт запускать скриптами этого кандидата.
   - Перенос коммита не делает проверки старого SHA проверками нового. После формирования кандидат заморожен;
     дальнейшие правки — только `FIX N`, новый SHA и повтор п. 3. Операции с веткой здесь — часть RELEASE 1 (D-10),
     без worktree/веток пула; по окончании вернуться в `dev`. Старые внутренние снимки карточек в кандидате не
     являются источником текущих статусов: они ведутся в `dev` и исключены из пакета через `.pubignore`.
3. **Проверки на одном SHA РК.** Результаты пула на том же SHA засчитываются; на другом SHA — повтор.
   - Windows: `bash tool/ci/scope_guard.sh 0.5.0` — ожидается `scope: all`. Локально выполнить
     `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/windows.ps1`, `pwsh -File tool/ci/android.ps1`,
     `pwsh -File tool/ci/web.ps1` (включая `--wasm`), `pwsh -File tool/ci/example.ps1`
     (с `$env:FLUTTER_VERSION='3.44.9'`), `pwsh -File tool/ci/smoke.ps1`: exit 0, критерии самих скриптов выполнены.
     Для `src/CMakeLists.txt` (номер версии) — также native CMake Release build и CTest по `AGENTS.md`.
   - Pixel 3 arm64 и armv7: `tool/probe/run_release_android.ps1` (Reviewer; засчитывается прогон пула на том же SHA).
   - Mac: покрывается CI `macos` и `ios`; pana — локально на Mac.
   - CI: новый уникальный тег `ci/all/0.5.1-<N>` (например, `ci/all/0.5.1-2`) на SHA РК; старый тег не передвигать.
     9/9 зелёные, `head_sha` у всех = новый SHA РК. Результаты `ci/all/0.5.1` и `ci/all/CI-4` — история своих SHA.
   - Пакет: `pana --exit-code-threshold 0 .` на Mac — 160/160; `flutter pub publish --dry-run` на чистом checkout
     SHA РК — 0 warnings.
   - После прогонов `git status` чистый; изменённое скриптами (`generated_plugin*`, lockfile) откатить.
4. **Отчёт Engineer.** SHA РК, таблица «проверка → машина → команда → exit → результат», таблица workflow → run,
   Pixel 3, итог аудита четырёх документов, состав кандидата A1/A2, известные ограничения
   (Safari/Firefox not verified; JavaScript и `--wasm` — проверенные случаи Chrome) и команды:
   ```sh
   git switch release/0.5.1 && git rev-parse HEAD   # = SHA РК
   git push origin release/0.5.1
   git tag -a 0.5.1 -m "Released yuv_ffi 0.5.1" <SHA РК>
   git push origin 0.5.1
   flutter pub publish
   git push origin <SHA РК>:main                    # fast-forward: main — предок release/0.5.1
   git switch dev
   ```
5. **После публикации (Engineer или роль по его команде).** Удалить теги `ci/*` локально и на origin, записать
   выпуск в `COMPLETION.md`, удалить карточку, перевести `todo.md` на следующий цикл. После перевода `main` на
   SHA выпуска Engineer синхронизирует его с `dev` по правилу 11: `git switch dev`, `git fetch origin`,
   `git merge origin/main`. Особенно для A1: перенесённый коммит имеет другой SHA, чем коммит документов в `dev`.
   Если `origin/main` уже предок `dev`, merge не нужен; факт подтвердить `git merge-base --is-ancestor origin/main dev`.

#### Scope

`release/0.5.1`, записи в `todo.md` и `COMPLETION.md`, удаление рабочих артефактов, найденных пунктом 1. Исправления —
только карточками `FIX N`.

#### Constraints

- Аудит не правит код. Не ставить тег, не публиковать, не менять `main` — это Engineer.
- Не менять золотые эталоны и baseline проб ради зелёного гейта.
- Отсутствие машины или браузера — «не проверено» с причиной, не PASS. Pixel 3 — только `adb install -r`.

#### Definition of Done

1. FIX 1 принята; новый кандидат содержит её четыре документа, состав A1/A2 записан — check: принятое ревью FIX 1,
   сравнение документов и diff кандидата — by: Executor.
2. Аудит всех областей п. 1 без блокеров или они закрыты `FIX N` — check: таблица аудита, включая MIGRATION и
   README примера — by: Executor.
3. На одном новом SHA РК: локальные проверки п. 3, новый `ci/all/0.5.1-<N>` 9/9, pana 160/160, dry-run без warnings,
   чистое дерево — check: команды с exit code, счётчиками и `head_sha` каждого run — by: Executor.
4. Pixel 3 arm64 и armv7 прошли на том же новом SHA — check: `tool/probe/run_release_android.ps1 -GitSha <SHA РК>
   -Abi arm64` и отдельно `-Abi armv7`, exit 0, smoke/probe PASS, 1188 в каждом — by: Reviewer.
5. Отчёт Engineer по п. 4 готов, текущие результаты/ожидаемые действия отделены от истории `61da2ee` — check:
   Executor Report и Review с новым SHA и актуальными командами выпуска — by: Executor, Reviewer.

#### Validation

- Executor: команды пунктов 1–3 с новым SHA и exit code; проверки dry-run и Web `--wasm` входят в его гейт.
  После формирования кандидата `git diff --check 0.5.0..<SHA РК>` — exit 0; чтением сравнить четыре документа с
  принятым коммитом FIX 1. Для A1 `git diff --exit-code 61da2ee..<SHA РК> -- lib src assets shaders darwin android
  example/lib example/integration_test tool .github pubspec.yaml example/pubspec.lock` — exit 0.
- Reviewer: прочитать diff и отчёт против DoD, сверить `head_sha` всех новых run; выполнить назначенные ему
  Pixel 3 arm64/armv7 и записать результаты. Успешные проверки Executor повторно не назначаются Reviewer.

#### Executor Report

##### История прежнего кандидата — 05.10.2026

Сохранённый отчёт ниже относится к `61da2ee`. Строки «ожидает выполнения» и Engineer attention описывают момент
сдачи Executor; соответствующие проверки выполнены в историческом Review. Для нового кандидата Executor
добавляет отдельный подраздел с новым `Validated at`, таблицами аудита/проверок и текущим следующим шагом.

Validated at: `61da2ee3457ee81e1ab7de99bbf54d3170f1fde1`

1. Аудит диапазона `0.5.0..61da2ee` — без блокирующих находок:

   | Область | Что проверено | Результат |
   | --- | --- | --- |
   | CHANGELOG | `## 0.5.1` против изменений диапазона | Описаны уточнение статуса Web/платформ и поддержка операций `--wasm`; внутренних изменений нет. |
   | README | Requirements, Platform status, Web backend против `doc/web-parity.md` | Согласованы; Safari/Firefox — “not verified”; iOS ручная проверка указана как release build. |
   | Версия | `pubspec.yaml`, CHANGELOG, podspec, `src/CMakeLists.txt`, README, `example/pubspec.lock` | Везде `0.5.1`; в `src/` изменён только номер версии. |
   | API | `lib/yuv_ffi.dart`, `test/public_surface_test.dart` | Оба файла не менялись. |
   | Следы разработки | Изменённые Dart-файлы в `lib/`: `TODO`/`FIXME`, ID задач, `print`/`debugPrint`, новые `ignore` | Не найдены. |
   | Пакет и артефакты | `flutter pub publish --dry-run`; `git status --short --ignored`; состав `tasks/0.5.1/` | Dry-run — 0 warnings, архив 678 KB; после проверок нет новых tracked/untracked артефактов; на кандидате в папке задач только RELEASE 1. |

2. Релиз-кандидат — ветка `release/0.5.1`, SHA `61da2ee3457ee81e1ab7de99bbf54d3170f1fde1`; проверенные файлы и версии на SHA не менялись после прогона.

3. Проверки на одном SHA:

   | Проверка | Машина / команда | Результат |
   | --- | --- | --- |
   | Scope | Windows: `bash tool/ci/scope_guard.sh 0.5.0` | exit 0, `scope: all`. |
   | VM | Windows: `pwsh -File tool/ci/vm.ps1` | exit 0, 638/638. |
   | Windows | Windows: `pwsh -File tool/ci/windows.ps1` | exit 0, 134/134; Release build и пять integration targets. |
   | Android | Windows: `pwsh -File tool/ci/android.ps1` | exit 0; ABI split builds и пять integration targets. Первый запуск встретил занятый Kotlin cache; повтор после окончания параллельной Gradle-сборки прошёл. |
   | Web | Windows: `pwsh -File tool/ci/web.ps1` | exit 0; JavaScript 14 sources/64 cases, reference 119, camera smoke 1; три `--wasm` цели прошли. |
   | Example | Windows, `FLUTTER_VERSION=3.44.9`: `pwsh -File tool/ci/example.ps1` | exit 0; analyze и Web build. |
   | Smoke | Windows: `pwsh -File tool/ci/smoke.ps1` | exit 0. |
   | Native C | Windows: CMake Release build и CTest | exit 0; 11/11. |
   | pana | Mac: `pana --exit-code-threshold 0 .` | exit 0; 160/160. |
   | Publish dry-run | Windows: `flutter pub publish --dry-run` | exit 0; 0 warnings. |
   | Pixel 3 | Reviewer: `tool/probe/run_release_android.ps1` для arm64 и armv7 | Ожидает выполнения на этом кандидате. |

   `ci/all/0.5.1` — все девять workflow завершились `success`, `head_sha` у каждого равен SHA кандидата:

   | Workflow | Run |
   | --- | --- |
   | CI Android | [37286266754](https://github.com/Anfet/yuv_ffi/actions/runs/37286266754) |
   | CI | [37286266772](https://github.com/Anfet/yuv_ffi/actions/runs/37286266772) |
   | Example CI | [37286266787](https://github.com/Anfet/yuv_ffi/actions/runs/37286266787) |
   | CI smoke | [37286266823](https://github.com/Anfet/yuv_ffi/actions/runs/37286266823) |
   | CI VM | [37286266805](https://github.com/Anfet/yuv_ffi/actions/runs/37286266805) |
   | iOS CI | [37286266918](https://github.com/Anfet/yuv_ffi/actions/runs/37286266918) |
   | CI macOS | [37286266963](https://github.com/Anfet/yuv_ffi/actions/runs/37286266963) |
   | CI Web | [37286266838](https://github.com/Anfet/yuv_ffi/actions/runs/37286266838) |
   | CI Windows | [37286266885](https://github.com/Anfet/yuv_ffi/actions/runs/37286266885) |

4. Engineer report: кандидат — `61da2ee3457ee81e1ab7de99bbf54d3170f1fde1`; результаты аудита и таблицы workflow/проверок приведены выше. Safari/Firefox не проверялись; Web `--wasm` проверен в Chrome. CI trigger tag `ci/all/0.5.1` указывает на этот SHA. После Reviewer PASS команды Engineer:

   ```sh
   git switch release/0.5.1 && git rev-parse HEAD   # = 61da2ee3457ee81e1ab7de99bbf54d3170f1fde1
   git push origin release/0.5.1
   git tag -a 0.5.1 -m "Released yuv_ffi 0.5.1" 61da2ee3457ee81e1ab7de99bbf54d3170f1fde1
   git push origin 0.5.1
   flutter pub publish
   git push origin 61da2ee3457ee81e1ab7de99bbf54d3170f1fde1:main
   git switch dev
   ```

   Тег выпуска, публикация и изменение `main` не выполнялись.

Deviations: локальный Android script сначала остановился при удалении Kotlin cache, пока параллельная Gradle-сборка другого проекта использовала Flutter SDK; после завершения той сборки повторный запуск прошёл. Все проверки Executor на кандидате успешны. После завершения проверок в общей копии `dev` появились посторонние staged `tool/ci/web.sh` и untracked `tasks/0.5.2/`; они не входят в кандидат и не затронуты.

Engineer attention: Reviewer должен выполнить Pixel 3 arm64/armv7 и верификации из Validation на SHA кандидата; после этого Engineer подписывает гейт и выпускает пакет.

#### Review

##### История прежнего гейта — 05–06.10.2026

Ревью диапазона `1866a2d..61da2ee` и отчёта против карточки, 05.10.2026.

**Вердикт:** гейт пройден, принятый SHA РК — `61da2ee3457ee81e1ab7de99bbf54d3170f1fde1`. Статус `BLOCKED`: ждёт
подписи и выпуска Engineer (п. 4); закрытие карточки — п. 5 после публикации.

Проверено чтением:

- Аудит (выборочно): CHANGELOG `## 0.5.1` покрывает README/статус платформ и `--wasm`; README согласован с
  `doc/web-parity.md`, Safari/Firefox — «not verified»; `0.5.1` в `pubspec.yaml`, CHANGELOG, podspec,
  `src/CMakeLists.txt` (только номер), README, `example/pubspec.lock`; `lib/yuv_ffi.dart` и
  `test/public_surface_test.dart` не менялись с `0.5.0`; в добавленных строках `lib/` нет `TODO`/`FIXME`, ID задач,
  `print`, `ignore`; в `tasks/0.5.1/` на РК — только RELEASE 1.
- `ci/all/0.5.1` → `61da2ee`; все 9 run из отчёта — `completed/success`, `headSha` = `61da2ee…`.
- `1866a2d..61da2ee` меняет только `COMPLETION.md`, `todo.md`, `tasks/` — все в `.pubignore`; код и архив пакета
  совпадают с принятым SHA пула.

Прогоны Reviewer (причина 1 — Validation карточки), в локальном клоне `release/0.5.1` на `61da2ee`, дерево чистое:

| Проверка | Команда | Результат |
| --- | --- | --- |
| Pixel 3 arm64 | `tool/probe/run_release_android.ps1 -GitSha 61da2ee… -Abi arm64` | exit 0; `RA25_HOST_RESULT` arm64-v8a, smoke PASS, probe PASS, 1188 |
| Pixel 3 armv7 | то же, `-Abi armv7` | exit 0; armeabi-v7a, smoke PASS, probe PASS, 1188 |
| Publish dry-run | `flutter pub publish --dry-run` | exit 0; `Package has 0 warnings`, 678 KB, `yuv_ffi.js`/`yuv_ffi.wasm` в архиве |
| Web `--wasm` | `tool/ci/drive.ps1 integration_test/probe_web_test.dart web-server --browser-name=chrome --headless --wasm` | exit 0; `PASS` (`All tests passed`) |

Блокирующих замечаний нет.

Замечание без возврата: п. 2 требует РК «без коммитов статуса», а `release/0.5.1` содержит коммиты статуса после
`1866a2d`. На пакет не влияет (только `.pubignore`-пути); пересоздание РК потребовало бы повтора всех проверок без
изменения кода.

Recommendations:

- После `git push origin 61da2ee:main` в `main` попадут внутренние `todo.md` и `tasks/0.5.1/RELEASE-1.md` в состоянии
  `IN_PROGRESS`/«не заморожен». Для будущих гейтов — ответвлять РК от принятого SHA кода, как пишет п. 2, или
  явно разрешить коммиты статуса в РК.

##### Финальный аудит — 06.10.2026

**Вердикт: PASS, блокирующих находок нет.** Принятый SHA РК остаётся
`61da2ee3457ee81e1ab7de99bbf54d3170f1fde1`. Дополнительно проверено состояние `dev` на
`8593f106bcb2d23231b4580663c84bbab640a744`: изменения после гейта рассмотрены отдельно и не подменяют результаты
проверок РК. `RELEASE 1` остаётся `BLOCKED` до решения и выпуска Engineer; CI 2, CI 3 и CI 4 закрыты.

| Область | Что проверено | Результат |
| --- | --- | --- |
| Изменения пакета | Diff `0.5.0..61da2ee` и `61da2ee..8593f10`; три изменённых файла `lib/`, их вызовы из загрузчика и WASM arena | Исправлены возврат числового статуса JS, распознавание JS-объекта и доступ к `HEAPU8`; новых блокирующих дефектов при чтении не найдено. После РК `lib/`, native-исходники, платформенные реализации, шейдеры и WASM-артефакты не менялись. |
| Публичный контракт | `lib/yuv_ffi.dart`, `test/public_surface_test.dart`, общие типы `lib/src/yuv/shared/` против `0.5.0` | Diff пуст; публичная поверхность сохранена. |
| Версии и документация | Четыре файла D-14, README, `example/pubspec.lock`, CHANGELOG и `doc/web-parity.md` | Версия `0.5.1` согласована; пользовательские изменения отражены. JavaScript и `--wasm` заявлены в пределах проверенного Chrome; Safari/Firefox не проверены. |
| Native и assets | Diff `src/`, `assets/`, `shaders/` против `0.5.0` | В `src/` изменены только два номера версии CMake; assets и шейдеры не изменены. Native CMake/CTest и device-пробы уже есть в отчёте РК. |
| Следы разработки | Добавленные строки `lib/`; итоговый diff тестов и CI | Новых `TODO`/`FIXME`, `print`/`debugPrint`, `ignore` нет. Временная диагностика, контрольный `RawImage` и изоляция агрегата отменены; assertions не ослаблены, skip/retry не добавлены. |
| CI после гейта | `web.sh`, `ci-web.yml`, итоговые изменения CI 3/CI 4 и их отчёты | Web CI перенесён на Mac; сохранены 14 источников/64 теста, reference 119, camera smoke и три обязательные `--wasm` цели. Изменения тестов — таймаут камеры по замеру и teardown двух widget-тестов. |
| Применимость проверок `dev` | `git diff a65270a..8593f10` по коду, тестам, example, CI, манифестам и внешней документации | Diff пуст. По принятому отчёту CI 4 локальные проверки exit 0, Mac `--wasm` 10/10, `ci/all/CI-4` 9/9 success на `a65270a`; успешные результаты остаются применимыми к этому состоянию `dev`. |
| Применимость гейта РК | Executor Report и Review этой карточки; ветка `release/0.5.1` | РК не изменён. Сохраняются `ci/all/0.5.1` 9/9, Pixel 3 arm64/armv7 по 1188, pana 160/160, dry-run 0 warnings и Web `--wasm`. Эти результаты относятся к `61da2ee`, а Mac CI после исправлений — к `a65270a`. |
| Состав и выпуск | `.pubignore`, активные карточки, `git status --short`, история веток | В `tasks/` только RELEASE 1; рабочее дерево перед записью аудита чистое. `main` — предок РК, fast-forward возможен. Тега `0.5.1` локально нет; выпуск в рамках аудита не выполнялся. |

Проверки Reviewer: чтение diff и отчётов; `git diff --check 0.5.0..8593f10` — exit 0;
`git merge-base --is-ancestor main release/0.5.1` — exit 0. Тесты и пробы повторно не запускались: новые изменения,
обесценивающие приведённые результаты на соответствующих SHA, отсутствуют (§2 правил Reviewer).

Recommendations:

- Исправления тестов CI 3/CI 4 и перенос Web CI на Mac отсутствуют в `release/0.5.1`. Зелёный Mac workflow на
  `a65270a` не означает, что старые тесты РК пройдут на Mac. Решение о переносе остаётся за Engineer (D-31 и
  рекомендации CI 4); если РК изменяется, записать новый SHA и повторить гейт по п. 3 Architect Decision.
- При сохранении РК `61da2ee` выпуск опирается на уже пройденный гейт этого SHA. Ограничение Safari/Firefox
  остаётся в документации; после публикации выполнить закрытие карточки и очистку CI-тегов по п. 5.

##### Требования после аудита — 07.10.2026

Engineer поставил повторную FIX 1 перед RELEASE 1. Аудит выявил устаревшее ограничение `--wasm` в MIGRATION и
несогласованный статус Web в README примера; они не были охвачены прежней таблицей аудита документации.
Поэтому прежний технический PASS остаётся фактом для `61da2ee`, а выпуск ждёт приёмки FIX 1 и гейта нового
кандидата по обновлённым требованиям. Рекомендация сохранить старый РК без изменений выше больше не является
текущим следующим шагом. Новое ревью заполняет Reviewer после отчёта нового кандидата.
