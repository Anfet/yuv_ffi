# RELEASE 1 — Финальный аудит и релизный гейт 0.5.0
**Status:** ACCEPTED · **Tier:** T2, Reviewer T1 + Engineer · **Owner:** — · **Depends On:** FIX 1, FIX 2, FIX 3, FIX 4 (DONE) · **Probe:** windows+pixel3
**Base SHA:** 4a485d8b8c1b5475bf0c02309b8d0dec56d0437c (Executor записывает SHA `dev` на старте)

#### Goal
Этапы 1–7 закрыты: код, example, документация, Web и Apple проверены по карточкам. Перед выпуском нужен один
независимый взгляд на весь релиз целиком — от опубликованной 0.4.0 (`origin/release/0.4.0`) до `dev` — и один
релизный гейт на одном SHA: версия `0.5.0`, ветка `release/0.5.0` (D-10), полный CI (D-23), Pixel 3, dry-run.
Итог — отчёт Engineer, по которому он ставит тег и публикует. Тег и публикация в задачу не входят.

#### Architect Decision
1. **Аудит (только чтение кода).** Первый статический проход записан в `doc/release-0.5.0-audit.md`; FIX 1–3 закрывают найденные блокеры. На принятом базовом SHA повторно проверить диапазон `origin/release/0.4.0..<base>` и дополнить документ независимыми результатами. Итоговая таблица «область → что проверено → находка → класс»:
   таблица «область → что проверено → находка → класс». Классы: **блокирует** (ломает заявленный сценарий,
   контракт данных/атомарности, публичное API без записи в CHANGELOG, неверный README), **после релиза**,
   **документировать**. Области:
   - публичное API: `lib/yuv_ffi.dart` и экспорты против `test/public_surface_test.dart`; каждое удаление и
     переименование есть в разделе Breaking changes `CHANGELOG.md` с миграцией;
   - `CHANGELOG.md` против `COMPLETION.md`: каждая принятая пользовательская задача отражена, нет записей о том, чего
     нет в коде;
   - `README.md` и `example/README.md`: таблица платформ, минимум Dart 3.12 / Flutter 3.44 (D-24), SPM и CocoaPods,
     ограничения Web — ровно как в `doc/web-parity.md` (частичный WASM, только Chrome проверен, `--wasm` не
     поддерживается); примеры кода соответствуют текущему API;
   - контракты из `.memory/MEMORY.md` («Контракты кода»): проверка до записи, ревизия растёт один раз, семантика
     blur — есть тест на каждый;
   - следы работы: `TODO`/`FIXME`, ID задач в коде и комментариях, `print`/`debugPrint` в `lib/`, `skip:` в тестах,
     мёртвый код, файлы вне `.pubignore`, которые не должны попасть в архив;
   - `pana` и состав архива: на чистом закоммиченном SHA `pana --exit-code-threshold 0 .` даёт полный балл и `flutter pub publish --dry-run` показывает только пакет и example; сохранить вывод и состав архива в отчёте.
   Новая блокирующая находка → отдельная карточка `FIX N` с решением (Executor пишет её как черновик, решение — Architect
   или Engineer); аудит продолжается до конца, затем `ENGINEER_REQUIRED`, если остался хотя бы один блокер.
2. **Версия.** Когда блокирующих находок нет: `0.5.0-dev.1` → `0.5.0` в `pubspec.yaml`, заголовке `CHANGELOG.md`,
   `darwin/yuv_ffi.podspec` и `YUV_FFI_PACKAGE_VERSION` в `src/CMakeLists.txt` (D-14). Других правок нет.
3. **Релиз-кандидат.** От этого SHA `dev` создать `release/0.5.0` (D-10) и записать SHA РК в `todo.md`. Дальше код
   заморожен: `lib/`, `src/`, `darwin/`, `android/`, `example/lib/`, `assets/` меняются только карточкой `FIX N`,
   после неё — новый SHA РК и повтор упавших проверок.
4. **Проверки на SHA РК.** Локально — все команды таблицы AGENTS.md (ключ `all`) на доступных
   машинах (Windows, Mac; Linux VM — если отвечает); `flutter test --tags probe`, `--tags reference` и native CTest
   (AGENTS.md, «Для `src/**`»). Тег `ci/all/0.5.0` на SHA `release/0.5.0` (D-23): все 9 workflow зелёные, ссылки — в
   отчёт. Pixel 3 — проба arm64 и armv7 (делает Reviewer, AGENTS.md «Пробы»).
5. **Браузеры.** Safari и Firefox проверяются, только если Engineer дал доступ (вопрос в `todo.md`); иначе в отчёте
   остаются «не проверено», как в `doc/web-parity.md`.
6. **Отчёт Engineer.** SHA РК, таблица workflow → run → результат, Pixel 3, итог аудита, известные ограничения
   (Web, `--wasm`, непроверенные браузеры), точные команды тега и публикации для Engineer.

#### Scope
`doc/release-0.5.0-audit.md`, повышение версии (решение 2), ветка `release/0.5.0`, записи в `todo.md` и
`COMPLETION.md`. Исправления — только отдельными карточками `FIX N`.

#### Constraints
- Аудит не правит код: находки записываются, не чинятся по ходу.
- Не ставить тег `v0.5.0`, не публиковать на pub.dev, не сливать в `main` — это Engineer.
- Не менять золотые эталоны и baseline проб ради зелёного гейта.
- Отсутствие машины или браузера — «не проверено» с причиной, не PASS.

#### Definition of Done
- `doc/release-0.5.0-audit.md` покрывает все области решения 1; блокирующих находок нет или все закрыты `FIX N`.
- FIX 1–3 приняты; инструкция установки в README указывает 0.5.0, браузерные ограничения согласованы с `doc/web-parity.md`, CHANGELOG не советует невыпущенную 0.4.2.
- Версия `0.5.0` одинакова в четырёх файлах D-14.
- `release/0.5.0` создана; на одном SHA РК зелёные локальные проверки, 9/9 workflow `ci/all/0.5.0`, Pixel 3 arm64 и
  armv7; `pana --exit-code-threshold 0 .` с полным баллом и `flutter pub publish --dry-run` (на чистом закоммиченном SHA) без предупреждений.
- Отчёт Engineer по решению 6 записан в Executor Report.

#### Validation
- Executor: команды решений 1–4 с SHA и exit code; `git diff --stat <РК> release/0.5.0 -- <замороженные пути>` пуст.
- Reviewer: выборочно перепроверить три находки аудита и три области «без находок»; повторить `dry-run` и одну
  пробу; пройти Pixel 3 arm64 и armv7; сверить ссылки run с SHA РК.

#### Executor Report

**STATUS: REVIEW**

**Повторный кандидат:** `release/0.5.0`, SHA `98ce7713e19f562cd6847dc34d1cdc394c283981`; tag `ci/all/0.5.0-v2` указывает на этот SHA. Локальная ветка кандидата обновлена с принятого `dev`; замороженные исходники после FIX 4 не менялись.

**Повторный CI:** все девять workflow прошли на SHA кандидата: Windows [37206274710](https://github.com/Anfet/yuv_ffi/actions/runs/37206274710), Smoke [37206274689](https://github.com/Anfet/yuv_ffi/actions/runs/37206274689), VM [37206274675](https://github.com/Anfet/yuv_ffi/actions/runs/37206274675), Android [37206274691](https://github.com/Anfet/yuv_ffi/actions/runs/37206274691), Linux и bindings [37206274713](https://github.com/Anfet/yuv_ffi/actions/runs/37206274713), macOS [37206274681](https://github.com/Anfet/yuv_ffi/actions/runs/37206274681), Web [37206274674](https://github.com/Anfet/yuv_ffi/actions/runs/37206274674), Example [37206274701](https://github.com/Anfet/yuv_ffi/actions/runs/37206274701), iOS [37206274709](https://github.com/Anfet/yuv_ffi/actions/runs/37206274709). Windows `tool/ci/windows.ps1` локально — exit 0, 20/20 групп, 1 skip.

**Повторный publish dry-run:** `flutter pub publish --dry-run` — exit 0, 0 warnings, 1 hint о версии 0.2.4 на pub.dev. `pana --exit-code-threshold 0 .` на Windows не запускается из-за ошибки sandbox самого pana: Windows `C:\...` путь отклонён как недопустимый из-за `:`. Предыдущий успешный результат Mac — 160/160 на SHA `f2130c2`; разница кандидата — синхронизация `example/pubspec.lock` для FIX 4. Новый pana-прогон на Mac не выполнен: локальный sync helper недоступен (нет `rsync`).

**Действие Reviewer:** повторить Pixel 3 arm64/armv7 и сверить кандидата и CI. Установку выполнять через `adb install -r`, сохранив данные приложения. Safari и Firefox остаются «не проверено» согласно решению Engineer.

**Release candidate:** `release/0.5.0`, SHA `f2130c2c5ccc64f314417f520146a075f8a5749b` (`ci/all/0.5.0` points to this SHA). Version `0.5.0` is consistent in `pubspec.yaml`, `CHANGELOG.md`, `darwin/yuv_ffi.podspec`, and `src/CMakeLists.txt`. `git diff --stat f2130c2..release/0.5.0 -- lib src darwin android example/lib assets` is empty.

**Audit:** `doc/release-0.5.0-audit.md` updated for base `4a485d8`. No new blocking source or documentation findings. Public-surface test passed; stale test-only commentary/optional `blank` implementation remains FOLLOWUP 1.

**Local validation on Windows:**

- `pwsh -File tool/ci/windows.ps1` — exit 0; 134/134 tests, native app/camera/presenter/probe/shader integration targets passed.
- `pwsh -File tool/ci/vm.ps1` — exit 0; 635/635, no skips.
- `pwsh -File tool/ci/android.ps1` — exit 0; Android ABI builds and five integration targets passed on emulator.
- `pwsh -File tool/ci/web.ps1` — exit 0; Chrome 154, 14 sources, 64 integration cases, 119 reference cases, camera smoke; committed WASM assets unchanged.
- `$env:FLUTTER_VERSION='3.44.9'; pwsh -File tool/ci/example.ps1` — exit 0; analyze and release Web build passed.
- `pwsh -File tool/ci/smoke.ps1` — exit 0.
- Native CMake Release build and CTest — exit 0; 11/11 passed.
- `flutter test --tags probe` — exit 0; 1,188/1,188 correctness cases. The performance-only test reported its configured skip.
- `flutter test --tags reference` — exit 0; 130 tests passed.

**Apple and Linux validation:** Mac runner `bash tool/ci/macos.sh` — exit 0; native build, packaging smoke, macOS Release/Debug, native integrations, and SPM/CocoaPods paths passed. Mac runner `bash tool/ci/ios.sh` — exit 0; CocoaPods install, simulator build and smoke passed. These were run from an archive snapshot derived from the candidate SHA. On 2026-10-04, Linux VM access was available; Flutter 3.44.9, CMake, and Xvfb were present. At candidate SHA `f2130c2`, Linux native Release build, Linux desktop Release build, app-runtime smoke, and all four native integration probes passed. `flutter pub get` changed `example/pubspec.lock` from `yuv_ffi 0.5.0-dev.1` to `0.5.0`, confirming the lockfile change reported by Linux CI; Linux CI itself remains failed pending Engineer direction. Safari and Firefox were not run, per the existing Engineer decision; README and `doc/web-parity.md` retain those limitations.

**Pixel 3:** arm64 and armv7 release probes passed on device `8B1X11QLW`. Both result markers name candidate SHA `f2130c2c5ccc64f314417f520146a075f8a5749b`, `smoke=PASS`, `probe=PASS`, `caseCount=1188`; arm64 run ID `7230ae06608c4fffb0c35eba6fa98683`, armv7 run ID `e4b01b1ec1cc4f5191814aa7dc920f2e`. APKs were installed with `adb install -r`; app data was retained. The armv7 probe used build number `10001` so its split APK could update the arm64 install without a downgrade.

**Package checks:** `pana --exit-code-threshold 0 .` — exit 0, 160/160 on Mac. `flutter pub publish --dry-run` — exit 0; archive 675 KB, package and example only, 0 warnings and one hint that the latest published version is 0.2.4.

**CI (`ci/all/0.5.0`):** all nine runs completed on candidate SHA `f2130c2c5ccc64f314417f520146a075f8a5749b`.

| Workflow | Result | Run |
| --- | --- | --- |
| Windows | PASS | [37200004950](https://github.com/Anfet/yuv_ffi/actions/runs/37200004950) |
| Smoke | PASS | [37200004954](https://github.com/Anfet/yuv_ffi/actions/runs/37200004954) |
| VM | PASS | [37200004964](https://github.com/Anfet/yuv_ffi/actions/runs/37200004964) |
| Android | PASS | [37200004960](https://github.com/Anfet/yuv_ffi/actions/runs/37200004960) |
| CI / Linux | FAIL — job `linux-native-smoke`, step `Build example (linux desktop)`; log: `git diff --exit-code pubspec.lock` returned 1 after `yuv_ffi 0.5.0 from path .. (was 0.5.0-dev.1 from path ..)`. | [37200004976](https://github.com/Anfet/yuv_ffi/actions/runs/37200004976) |
| macOS | FAIL — job `macos-native-smoke`, step `Run macOS native checks`; log: `The run changed tracked files: M example/pubspec.lock`. | [37200004967](https://github.com/Anfet/yuv_ffi/actions/runs/37200004967) |
| Web | PASS | [37200005009](https://github.com/Anfet/yuv_ffi/actions/runs/37200005009) |
| Example | PASS | [37200004952](https://github.com/Anfet/yuv_ffi/actions/runs/37200004952) |
| iOS | PASS | [37200005014](https://github.com/Anfet/yuv_ffi/actions/runs/37200005014) |

**Engineer attention:** 9/9 CI is not met. Per release-cycle rule 4, no CI diagnosis or source change is made in this pass. Decide whether to authorize a separate pass for the two reported workflow failures or to accept an explicit release exception. The release tag and publication have not been created.

#### Review

**Вердикт: не принято; требуется решение Engineer.** На SHA РК `f2130c2c5ccc64f314417f520146a075f8a5749b` релизный критерий 9/9 CI не выполнен: Linux [37200004976](https://github.com/Anfet/yuv_ffi/actions/runs/37200004976) и macOS [37200004967](https://github.com/Anfet/yuv_ffi/actions/runs/37200004967) завершились ошибкой. Оба run указывают на SHA РК. Linux log показывает единственный diff `example/pubspec.lock`: `yuv_ffi 0.5.0-dev.1` → `0.5.0`; macOS сообщает тот же изменённый отслеживаемый файл. В SHA РК `pubspec.yaml` уже содержит `0.5.0`, а `example/pubspec.lock` — `0.5.0-dev.1`. Локальный `vm.ps1` воспроизвёл это изменение lockfile; его вердикт тестов при этом PASS. Поэтому чистый локальный прогон не заменяет два упавших workflow.

**Независимая выборка аудита:** FIX 1 — внешние source/destination и отсутствие частичной записи проверены тестами `yuv_image_patch_test.dart` (15 PASS в `vm.ps1`); FIX 2 — README и `doc/web-parity.md` согласованы по Dart/Flutter, Chrome, Safari/Firefox и `--wasm`; FIX 3 — верхний CHANGELOG и README ведут с 0.4.0 к 0.5.0, API миграции совпадает с `YuvImage.copy()` без `blank`. Области без новых находок: экспортируемая поверхность и `public_surface_test.dart`, контракты ревизии/blur в `vm.ps1`, состав архива в повторном dry-run. Поиск следов в `lib/` и `src/` не выявил `TODO`/`FIXME` или печати; `skip:` в тестах соответствует условиям, перечисленным в аудите. Четыре версии D-14 совпадают; замороженные пути кандидата совпадают с `release/0.5.0`.

**Повторные проверки:** `pwsh -File tool/ci/vm.ps1` — exit 0, 635/635, 0 skip; `flutter test --no-pub test/probe/probe_correctness_test.dart` с собранной native DLL — exit 0, `cases=1188/1188`; `flutter pub publish --dry-run` — exit 0, архив 675 КБ, 0 warnings, 1 hint. Первичный прямой запуск трёх contract-файлов без native DLL не был валидной проверкой; вместо него использован штатный `vm.ps1`. Созданное локальными командами изменение `example/pubspec.lock` откатил до исходного чистого дерева. Pixel 3 arm64/armv7 Reviewer повторно не запускал: гейт уже заблокирован, после нового SHA РК пробы нужно пройти на обоих ABI вместе с упавшими CI.

**Решение Engineer:** рекомендую отдельную карточку `FIX N` для синхронизации `example/pubspec.lock` с `0.5.0`, затем новый SHA РК и повтор Linux/macOS CI и Pixel 3 по требованиям карточки. Альтернатива — явное исключение из релизного гейта; текущий DoD его не допускает без решения Engineer. Тег `v0.5.0` и публикация не выполнялись.

Engineer указал на исправление версии lockfile; работа оформлена как FIX 4. RELEASE 1 ждёт принятия FIX 4 и нового SHA РК.

**Повторное ревью после FIX 4 — принято Reviewer, ожидается подпись Engineer.** Кандидат `release/0.5.0` и тег `ci/all/0.5.0-v2` указывают на `98ce7713e19f562cd6847dc34d1cdc394c283981`; замороженные пути совпадают. Девять CI workflow завершились успешно на этом SHA, включая ранее упавшие Linux [37206274713](https://github.com/Anfet/yuv_ffi/actions/runs/37206274713) и macOS [37206274681](https://github.com/Anfet/yuv_ffi/actions/runs/37206274681). Версия `0.5.0` совпадает в четырёх файлах D-14 и `example/pubspec.lock`.

Reviewer повторил release-пробу на Pixel 3 `8B1X11QLW`: arm64 `7f3a9bb0f9264f6ea5552c3b2e9f119e`, armv7 `ccf512a9d24543f797edb0384bdf6b97`; оба маркера содержат SHA кандидата, `smoke=PASS`, `probe=PASS`, `caseCount=1188`. В обоих APK присутствует только нужный ABI и `libyuv_ffi.so`; установка выполнена `adb install -r` с сохранением данных. `flutter test --no-pub test/probe/probe_correctness_test.dart` с native DLL — PASS, `cases=1188/1188`; первая попытка без DLL была невалидной проверкой. `flutter pub publish --dry-run` — exit 0, 675 КБ, 0 warnings и 1 hint о предыдущей опубликованной версии. `pana --exit-code-threshold 0 .` на Mac в checkout точного SHA кандидата — exit 0, 160/160; Windows-версия `pana` падает на собственном ограничении sandbox для пути `C:\...`.

Блокирующих находок нет. После исправления lockfile повтор CI закрывает прежний отказ Linux/macOS; Safari и Firefox остаются «не проверено» по решению Engineer и ограничениям Web. Вспомогательный `tool/probe/run_release_android.ps1` вызывает `adb uninstall`, поэтому Reviewer выполнил эквивалентную release-пробу вручную с `install -r`; скрипт стоит привести к правилу сохранения данных после релиза. Тег `v0.5.0`, merge в `main` и публикация остаются решением Engineer.

**Перед выпуском для Engineer:** удалённая `origin/release/0.5.0` пока указывает на прежний `f2130c2`; локальная ветка и CI-тег указывают на принятый `98ce771`. После подписи выполнить из чистого checkout: `git switch release/0.5.0`, `git push origin release/0.5.0`, `git tag v0.5.0 98ce7713e19f562cd6847dc34d1cdc394c283981`, `git push origin v0.5.0`, `flutter pub publish`. Перед тегом сверить `git rev-parse HEAD` с принятым SHA. Публикация и тег в рамках ревью не выполнялись.
