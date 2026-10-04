# RELEASE 1 — Финальный аудит и релизный гейт 0.5.0
**Status:** ACCEPTED · **Tier:** T2, Reviewer T1 + Engineer · **Owner:** — · **Depends On:** FIX 5, FIX 6, FIX 7, FIX 8, FIX 9 · **Probe:** windows+pixel3
**Base SHA:** `df14dc8e5d42d9330d4bfa8592194a52d3a09556` (кандидат — `3e4c645`, см. отчёт)

Предыдущие раунды (кандидаты `f2130c2` и `98ce771`, CI `ci/all/0.5.0` и `ci/all/0.5.0-v2`, FIX 1–4) — в git-истории
этой карточки и в `COMPLETION.md`. Повторный финальный аудит 04.10.2026 нашёл новые блокеры: FIX 5 (презентер) и FIX 6
(документация от 0.2.4). Engineer вернул гейт на новый круг с дополненными требованиями.

#### Goal
Выпустить чистую 0.5.0: пакет, документация и CHANGELOG точны для пользователя опубликованной 0.2.4 (D-28). Все
проверки идут на одном SHA кандидата, в репозитории нет рабочих артефактов. Итог — отчёт Engineer, по которому он
ставит тег, публикует и вливает релиз в `main`. Тег, публикация и слияние в задачу не входят.

#### Architect Decision
1. **Аудит (только чтение кода).** На базовом SHA повторить аудит и переписать `doc/release-0.5.0-audit.md` целиком
   под этот раунд. Устаревшие строки про CI 7/9 и кандидат `f2130c2` не оставлять. Документ — таблица
   «область → что проверено → находка → класс» (классы: **блокирует**, **после релиза**, **документировать**).
   Области:
   - публичное API: `lib/yuv_ffi.dart` и экспорты против `test/public_surface_test.dart`. Каждое удаление и
     переименование относительно **0.2.4** (`git show 0.2.4:...`) и 0.4.0 есть в Breaking changes CHANGELOG или в
     таблице миграции README;
   - CHANGELOG против `COMPLETION.md`: каждая принятая пользовательская задача отражена; нет внутренних пунктов и
     записей о том, чего нет в коде; 0.4.0 помечена как отозванная (FIX 6);
   - README и example/README: переход описан с 0.2.4; нет невыпущенных версий (0.3.0 как релиз, 0.4.1, 0.4.2);
     таблица платформ и минимумы совпадают с `android/build.gradle`, podspec и `Package.swift`; ограничения Web — как
     в `doc/web-parity.md`; Safari и Firefox — «not verified» (D-27);
   - **сниппеты README компилируются:** временный пакет вне репозитория с path-зависимостью; каждый Dart-блок и все
     методы таблицы миграции; `flutter analyze` без ошибок;
   - **контракты новых API 0.5.0 по dartdoc:** для `YuvFramePresenter`/`YuvFrameView`, `YuvFrameRenderer`,
     `YuvFrameGeometry`, `pack()`, `applyPatch()`, `YuvImageProvider` каждое обещание dartdoc об ошибках, владении
     кадром и состоянии после исключения покрыто тестом. Обещание без теста — находка;
   - контракты из `.memory/MEMORY.md` («Контракты кода»): на каждый есть тест;
   - следы работы: `TODO`/`FIXME`, ID задач и `print`/`debugPrint` в `lib/` и опубликованном example; мёртвые
     `ignore`; `skip:` в тестах; комментарии об удалённом API (FIX 7);
   - **состав репозитория и рабочего дерева:** в архиве (`dry-run`) только пакет и example; в `assets/` только
     используемые файлы; в корне нет неотслеживаемых и игнорируемых артефактов, кроме `build/`, `.dart_tool/`,
     `pubspec.lock` и IDE-каталогов (`git status --short --ignored`); в `tasks/0.5.0/` только активные карточки.
   Новая блокирующая находка — черновик `FIX N` с решением (решение — Architect или Engineer). Аудит идёт до конца,
   затем `ENGINEER_REQUIRED`, если остался хотя бы один блокер.
2. **Версия.** `0.5.0` уже стоит в четырёх файлах D-14 и `example/pubspec.lock`; проверить, не менять.
3. **Релиз-кандидат.** `release/0.5.0` перемотать на принятый SHA `dev` (fast-forward) и записать новый SHA РК в
   `todo.md`. Дальше заморозка: `lib/`, `src/`, `darwin/`, `android/`, `example/lib/`, `assets/`, `README.md`,
   `CHANGELOG.md` меняются только карточкой `FIX N`, после неё — новый SHA РК и **полный** повтор пункта 4.
4. **Все проверки — на одном SHA РК.** Результаты прежних SHA не переносятся, даже при «эквивалентной» разнице.
   - Windows: `vm.ps1`, `windows.ps1`, `android.ps1`, `web.ps1`, `example.ps1` (`FLUTTER_VERSION=3.44.9`),
     `smoke.ps1`; native CMake Release + CTest; `flutter test --tags probe` и `--tags reference`.
   - Mac: `bash tool/ci/macos.sh`, `bash tool/ci/ios.sh` из checkout или архива точного SHA РК.
   - Linux VM: сборка и интеграционные цели по AGENTS.md («Локальные проверки», `linux`); VM не отвечает — «не
     проверено» с причиной.
   - CI: тег `ci/all/0.5.0-v3` на SHA РК, все 9 workflow зелёные, ссылки на run и сверка `head_sha` — в отчёте.
   - Pixel 3 arm64 и armv7: `tool/probe/run_release_android.ps1` после FIX 8, без удаления приложения (делает Reviewer).
   - Пакет: `pana --exit-code-threshold 0 .` на Mac (160/160) и `flutter pub publish --dry-run` на Windows — на чистом
     checkout SHA РК; вывод и состав архива — в отчёт.
   - После всех прогонов `git status` чистый; изменённое скриптами (`generated_plugin*`, lockfile) откатить и записать.
5. **Браузеры.** Safari и Firefox не проверяются (D-27): в отчёте и документах — «not verified».
6. **Отчёт Engineer.** SHA РК, таблица «проверка → машина → команда → exit → результат», таблица workflow → run,
   Pixel 3, итог аудита, известные ограничения (Web, `--wasm`, Safari/Firefox not verified) и точные команды из
   чистого checkout:
   ```sh
   git switch release/0.5.0 && git rev-parse HEAD   # = SHA РК
   git push origin release/0.5.0
   git tag -a 0.5.0 -m "Released yuv_ffi 0.5.0" <SHA РК>   # как 0.4.0: аннотированный, без префикса v
   git push origin 0.5.0
   flutter pub publish
   ```
   Затем слить `release/0.5.0` в `main` через PR (ветка по умолчанию на GitHub, сейчас на 0.2.3).
7. **После публикации (Orchestrator, с разрешения Engineer).** Удалить теги `ci/*` локально и на origin (правило 4) и
   устаревшие ветки (`ci/stage2-probes`, `docs/RA-60-architect`, `task/RA-60` локально и на origin), записать
   публикацию в `COMPLETION.md`, перевести карточку в `DONE`.

#### Scope
`doc/release-0.5.0-audit.md`, ветка `release/0.5.0`, записи в `todo.md` и `COMPLETION.md`, удаление рабочих
артефактов, найденных пунктом 1. Исправления — только отдельными карточками `FIX N`.

#### Constraints
- Аудит не правит код: находки записываются, не чинятся по ходу.
- Не ставить тег `0.5.0`, не публиковать на pub.dev, не сливать в `main` — это Engineer.
- Не менять золотые эталоны и baseline проб ради зелёного гейта.
- Отсутствие машины или браузера — «не проверено» с причиной, не PASS.
- Pixel 3 — только `adb install -r`, без удаления приложения и очистки данных.

#### Definition of Done
- `doc/release-0.5.0-audit.md` переписан под этот раунд и покрывает все области решения 1; блокирующих находок нет
  или все закрыты `FIX N`.
- README и CHANGELOG описывают переход с 0.2.4; сниппеты компилируются; невыпущенных версий нет; 0.4.0 — retracted.
- Версия `0.5.0` одинакова в четырёх файлах D-14 и `example/pubspec.lock`.
- На одном SHA РК: все локальные проверки решения 4, 9/9 CI `ci/all/0.5.0-v3`, Pixel 3 arm64 и armv7, pana 160/160,
  dry-run без warnings. Дерево чистое, рабочих артефактов нет.
- Отчёт Engineer по решению 6 записан в Executor Report.

#### Validation
- Executor: команды решений 1–4 с SHA и exit code; `git diff --stat <РК> release/0.5.0 -- <замороженные пути>` пуст;
  у каждого результата отчёта указан один и тот же SHA РК.
- Reviewer: выборочно перепроверить три находки аудита и три области «без находок», компиляцию сниппетов README и
  тест FIX 5. Повторить dry-run и одну пробу, пройти Pixel 3 arm64 и armv7 скриптом FIX 8, сверить `head_sha` всех
  run с SHA РК.

#### Executor Report

**Статус: REVIEW (ждёт Reviewer: Pixel 3 и независимая проверка; затем Engineer).**

**SHA РК: `3e4c645798032149d301f548237664d9251e9c43`** (`release/0.5.0` = `dev` на этом SHA, fast-forward с `98ce771`; не запушен). Base SHA старта: `df14dc8`; прогон на `df14dc8` дал `pana` 150/160 (формат трёх файлов `lib/`) и отменён, результаты на нём не переносятся. Закрыто FIX 10 (`3e4c645`, чисто форматная правка). `git diff df14dc8 3e4c645 -- lib src darwin android example/lib assets README.md CHANGELOG.md` — только перенос строк и пробелы (`git diff -w` подтверждает).

| Проверка | Машина | Команда | Exit | Результат |
| --- | --- | --- | --- | --- |
| smoke | Windows | `pwsh -File tool/ci/smoke.ps1` | 0 | PASS |
| vm | Windows | `pwsh -File tool/ci/vm.ps1` | 0 | PASS (на `df14dc8` было 638/638) |
| windows (+ `--tags probe`, `--tags reference`) | Windows | `pwsh -File tool/ci/windows.ps1` | 0 | PASS |
| example | Windows | `FLUTTER_VERSION=3.44.9 pwsh -File tool/ci/example.ps1` | 0 | PASS |
| web | Windows | `pwsh -File tool/ci/web.ps1` | 0 | PASS |
| android (эмулятор) | Windows | `pwsh -File tool/ci/android.ps1` | 0 | PASS |
| native CMake Release + CTest | Windows | `cmake -S . -B <temp> -DBUILD_TESTING=ON`, `--build --config Release`, `ctest -C Release` | 0 | 11/11 |
| macos | Mac | `bash tool/ci/macos.sh` (архив SHA РК) | 0 | PASS |
| ios | Mac | `bash tool/ci/ios.sh` (архив SHA РК) | 0 | PASS |
| pana | Mac | `pana --exit-code-threshold 0 .` | 0 | **160/160** |
| dry-run | Windows | `flutter pub publish --dry-run` на чистом export SHA РК | 0 | 0 warnings, 1 hint (предыдущая версия 0.2.4), архив 678 КБ: только пакет, example, `MIGRATION.md`, `assets/` |
| Linux VM | — | — | — | **не проверено:** SSH на VM — таймаут; Linux покрыт workflow `CI` |
| Pixel 3 arm64/armv7 | — | `tool/probe/run_release_android.ps1` | — | делает Reviewer |

Отдельные `flutter test --tags probe|reference` вне `windows.ps1` падали (нет `yuv_ffi.dll`) — ошибка запуска, не кода; зачёт — прогон внутри `windows.ps1`, который собирает DLL.

CI `ci/all/0.5.0-v4`, 9/9 success, `head_sha` у всех = SHA РК:

| Workflow | Run |
| --- | --- |
| CI (Linux) | [37229763307](https://github.com/Anfet/yuv_ffi/actions/runs/37229763307) |
| CI VM | [37229763318](https://github.com/Anfet/yuv_ffi/actions/runs/37229763318) |
| CI Windows | [37229763303](https://github.com/Anfet/yuv_ffi/actions/runs/37229763303) |
| CI Android | [37229763281](https://github.com/Anfet/yuv_ffi/actions/runs/37229763281) |
| CI Web | [37229763298](https://github.com/Anfet/yuv_ffi/actions/runs/37229763298) |
| Example CI | [37229763310](https://github.com/Anfet/yuv_ffi/actions/runs/37229763310) |
| CI macOS | [37229763305](https://github.com/Anfet/yuv_ffi/actions/runs/37229763305) |
| iOS CI | [37229763313](https://github.com/Anfet/yuv_ffi/actions/runs/37229763313) |
| CI smoke | [37229763294](https://github.com/Anfet/yuv_ffi/actions/runs/37229763294) |

**Аудит:** `doc/release-0.5.0-audit.md`. Блокер один (формат `lib/`), закрыт FIX 10. После релиза: тест асинхронных ошибок `YuvFramePresenter.present`; 419 мёртвых `ignore: deprecated_member_use_from_same_package` в `test/`. Документировать: `card: DEVICE-1` в JSON example (FIX 7), README «not tested» вместо «not verified», строка iOS про debug. Сниппеты README и вызовы таблицы миграции компилируются (`flutter analyze` чисто). Удалены рабочие артефакты `analyze-rework.log`, `doc/api/`. Версия 0.5.0 в четырёх файлах D-14 и `example/pubspec.lock` не менялась.

**Известные ограничения:** Web — частичный WASM backend; `flutter build web --wasm` собирается, но операции падают в runtime; Safari и Firefox — not verified (D-27).

**Команды Engineer** (после ревью и Pixel 3):

```sh
git switch release/0.5.0 && git rev-parse HEAD   # = 3e4c645798032149d301f548237664d9251e9c43
git push origin release/0.5.0
git tag -a 0.5.0 -m "Released yuv_ffi 0.5.0" 3e4c645798032149d301f548237664d9251e9c43
git push origin 0.5.0
flutter pub publish
```

Затем слить `release/0.5.0` в `main` через PR. После публикации — удалить теги `ci/*` (локально и на origin; сейчас есть и `ci/all/0.5.0-v3`, `-v4`) и устаревшие ветки (п. 7 решения).

#### Review

**ACCEPTED, 04.10.2026.** Принят SHA РК `3e4c645798032149d301f548237664d9251e9c43`; диапазон
`df14dc8e5d42d9330d4bfa8592194a52d3a09556..3e4c645` и отчёт `7266274`. Блокирующих замечаний нет.
Релизная ветка остаётся на SHA РК; правки Reviewer затрагивают только внутренние документы в `dev`.
Публикация, тег `0.5.0`, push релизной ветки и слияние в `main` — решение Engineer; карточка остаётся до публикации.

Проверки выполнены на отдельных временных checkout точного SHA РК, без worktree и делегирования.

| Проверка Reviewer | Команда / машина | Exit | Результат |
| --- | --- | --- | --- |
| FIX 5 и публичные контракты | Windows: `flutter test test/yuv_frame_presenter_test.dart test/public_surface_test.dart test/yuv_image_patch_test.dart test/yuv_pack_test.dart test/yuv_frame_geometry_test.dart test/yuv_frame_renderer_test.dart --reporter expanded`, DLL собрана через `New-CiNativeBuild` из SHA РК | 0 | 55/55 PASS; обе проверки синхронного сбоя presenter и следующий показанный кадр прошли |
| Независимая native-проба | Windows: `flutter test test/probe/probe_correctness_test.dart --reporter expanded`, DLL в PATH | 0 | `PROBE scope: ops=all formats=all cases=1188/1188`; PASS, встроенный негативный контроль прошёл |
| Формат FIX 10 | Windows: `dart format --output=none --set-exit-if-changed lib` | 0 | 46 файлов, 0 изменений |
| Сниппеты и миграция | Windows, временный пакет с path-зависимостью на checkout SHA РК: `flutter pub get`, `flutter analyze` | 0 | `No issues found`; автоматически извлечены все 7 Dart-блоков README и 1 блок MIGRATION.md; отдельно вызваны методы всех строк таблицы миграции |
| Пакет | Windows: `flutter pub publish --dry-run` после восстановления трёх `example/windows/flutter/generated_plugin*` в проверочном checkout | 0 | 0 warnings, 1 version hint (0.2.4), 678 КБ; MIGRATION.md и WASM входят, внутренние карточки/отчёты/тесты не входят; `git status --short` пуст |
| Pixel 3 arm64 | `pwsh -File tool/probe/run_release_android.ps1 -GitSha 3e4c645798032149d301f548237664d9251e9c43 -Serial 8B1X11QLW -Abi arm64` | 0 | smoke PASS, probe PASS, 1188/1188; APK только arm64-v8a, установка `adb install -r` |
| Pixel 3 armv7 | Та же команда с `-Abi armv7`, после восстановления сгенерированных Windows-файлов в checkout | 0 | smoke PASS, probe PASS, 1188/1188; APK только armeabi-v7a, установка `adb install -r` |
| CI и SHA | `gh run list --repo Anfet/yuv_ffi --commit 3e4c645798032149d301f548237664d9251e9c43 --limit 30 --json databaseId,workflowName,headSha,conclusion,status,url,headBranch` | 0 | Все 9 run из Executor Report: completed/success, head_sha точно SHA РК, тег `ci/all/0.5.0-v4` |

CI v4 заменил v3 после FIX 10 и смены кандидата; результаты предыдущего SHA не использованы. Linux VM локально
не проверена (Executor: SSH timeout); Linux CI на точном SHA РК — success. Mac/pana не перезапускались Reviewer:
проверены соответствующие CI run и SHA, локальные результаты Mac остаются свидетельством Executor.

**Выборочная перепроверка аудита:** три области с находками — формат, контракты dartdoc/тесты, следы работы;
три области без находок — публичное API/миграция относительно 0.2.4 и 0.4.0, компиляция сниппетов, состав пакета
и согласованность версий. Сверены старые экспорты и методы с MIGRATION.md, четыре версии D-14 и
`example/pubspec.lock` равны 0.5.0, в `assets/` только два используемых WASM-файла. Новых блокеров нет.
Небольшие однозначные замечания исправлены по правилу 8 `todo.md`: аудит переведён на новый SHA и закрытый FIX 10;
удалена ошибочная находка про fragment (`_expectPatch` прямо сравнивает все его байты), число мёртвых ignore
уточнено до 419 в 25 файлах, число Dart-блоков README — до 7. Остался долг после релиза: тест асинхронной ошибки
декодирования/загрузки presenter и уборка ignore. Ограничения Web, `--wasm`, Safari/Firefox not verified сохранены.

**Логи и доказательства** (вне репозитория, под `C:/Users/Oleg-T/AppData/Local/Temp/`):
- `yuv-release-review-verify-native.log`: сборка DLL, 55/55, проба 1188/1188 и формат; первый dry-run в нём отклонён
  из-за generated_plugin*, окончательный успешный — `yuv-release-review-publish.log`.
- `yuv-release-review-snippets.log`, фикстуры `yuv-release-snippets-b9785bec/lib/`.
- `yuv-release-review-pixel.log` — arm64 PASS; общая оболочка затем вернула 1 на проверке чистоты перед armv7
  из-за generated_plugin*. После восстановления этих файлов armv7 повторён: `yuv-release-review-pixel-armv7.log`, exit 0.
- Host/device JSON: `yuv_ffi-ra25-release/ra25-arm64-16b13faac109454da6118c13ab189ab6-{host,device}.json` и
  `ra25-armv7-c2f43e41b2794eab8a2d4fdf18db9059-{host,device}.json`; gitSha/revision, ABI и строгий RA25_RESULT сверены.
- APK SHA256: arm64 `e588637daf7c86394c318b7a06f0f7002bffe4898b4d6ef0b0358ea595dc4e4b`,
  armv7 `877db4bcbc2dc2f38c0703aba5c3f3c2658d087916cfbefb1cc50df6736577ab`.

Первый запуск целевых тестов без DLL дал ошибки загрузки native library; после сборки DLL весь набор прошёл.
Основная копия оставалась в `dev`, без изменений кода. Процессы проверок завершены; приложение пробы остановлено,
данные не удалялись. Memory: без изменений.
