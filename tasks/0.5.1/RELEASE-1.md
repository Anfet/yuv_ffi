# RELEASE 1 — Релизный гейт 0.5.1
**Status:** REVIEW · **Tier:** T2, Reviewer T1 + Engineer · **Owner:** Reviewer · **Depends On:** — · **Probe:** windows+pixel3+web

**Base SHA:** `1866a2d155cc241b1e0b0af7f71e23398b2637e1` (принятый SHA пула `WASM`)

**Release candidate:** `release/0.5.1` at `61da2ee3457ee81e1ab7de99bbf54d3170f1fde1`

#### Goal

Выпустить 0.5.1: изменения относительно опубликованной 0.5.0 точно описаны в CHANGELOG и README, все проверки — на
одном SHA кандидата, в репозитории нет рабочих артефактов. Итог — отчёт Engineer, по которому он ставит тег,
публикует и переводит `main`. Тег, публикация и `main` в задачу не входят.

#### Architect Decision

1. **Аудит разницы (только чтение).** Диапазон `0.5.0..<SHA>`; результат — таблица «область → что проверено →
   находка» в Executor Report (отдельного файла аудита нет):
   - CHANGELOG `## 0.5.1` против изменений диапазона: каждое пользовательское изменение есть, внутренних пунктов нет;
   - README: «Requirements», «Platform status», «Web backend» согласованы с `doc/web-parity.md`; Safari и Firefox —
     «not verified» (D-27);
   - версия `0.5.1` в четырёх файлах D-14, README и `example/pubspec.lock`;
   - публичное API не изменилось: `lib/yuv_ffi.dart` и `test/public_surface_test.dart` — без изменений или проходят;
   - следы работы в изменённых файлах `lib/`: `TODO`/`FIXME`, ID задач, `print`/`debugPrint`, новые `ignore`;
   - состав: архив dry-run — только пакет, example, `MIGRATION.md`, `assets/`; `git status --short --ignored` — без
     новых артефактов; в `tasks/0.5.1/` — только активные карточки.
   Блокирующая находка — черновик `FIX N` и `ENGINEER_REQUIRED`.
2. **Релиз-кандидат.** `release/0.5.1` от принятого SHA пула (код, без коммитов статуса); SHA — в `todo.md`. Дальше
   заморозка: правка — только `FIX N`, затем новый SHA и повтор пункта 3.
3. **Проверки на одном SHA РК.** Результаты пула на том же SHA засчитываются; на другом SHA — повтор.
   - Windows: ключи `bash tool/ci/scope_guard.sh 0.5.0` (ожидаются `vm`, `windows`, `web` с `--wasm`, `example` с
     `FLUTTER_VERSION=3.44.9`, `smoke`; `src/CMakeLists.txt` изменён только номером версии — native CMake Release +
     CTest).
   - Pixel 3 arm64 и armv7: `tool/probe/run_release_android.ps1` (Reviewer; засчитывается прогон пула на том же SHA).
   - Mac: покрывается CI `macos` и `ios`; pana — локально на Mac.
   - CI: тег `ci/all/0.5.1` на SHA РК, 9/9 зелёные, `head_sha` у всех = SHA РК.
   - Пакет: `pana --exit-code-threshold 0 .` на Mac — 160/160; `flutter pub publish --dry-run` на чистом checkout
     SHA РК — 0 warnings.
   - После прогонов `git status` чистый; изменённое скриптами (`generated_plugin*`, lockfile) откатить.
4. **Отчёт Engineer.** SHA РК, таблица «проверка → машина → команда → exit → результат», таблица workflow → run,
   Pixel 3, итог аудита, известные ограничения (Safari/Firefox not verified; `--wasm` — по итогу WEB 4) и команды:
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
   выпуск в `COMPLETION.md`, удалить карточку, перевести `todo.md` на следующий цикл.

#### Scope

`release/0.5.1`, записи в `todo.md` и `COMPLETION.md`, удаление рабочих артефактов, найденных пунктом 1. Исправления —
только карточками `FIX N`.

#### Constraints

- Аудит не правит код. Не ставить тег, не публиковать, не менять `main` — это Engineer.
- Не менять золотые эталоны и baseline проб ради зелёного гейта.
- Отсутствие машины или браузера — «не проверено» с причиной, не PASS. Pixel 3 — только `adb install -r`.

#### Definition of Done

- Аудит разницы без блокеров или все блокеры закрыты `FIX N`.
- На одном SHA РК: проверки пункта 3, `ci/all/0.5.1` 9/9, Pixel 3 arm64 и armv7, pana 160/160, dry-run без warnings;
  дерево чистое.
- Отчёт Engineer по пункту 4 — в Executor Report.

#### Validation

- Executor: команды пунктов 1–3 с SHA и exit code; у каждого результата один и тот же SHA РК.
- Reviewer: выборочно перепроверить аудит, повторить dry-run и одну Web-пробу `--wasm`, сверить `head_sha` всех run.

#### Executor Report

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
