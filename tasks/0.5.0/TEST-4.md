# TEST 4 — Карта «что изменил → что запускать»
**Status:** TODO · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** TEST 2, TEST 3 · **Rejection Count:** 3
**Было:** RA-62 (цикл 0.4.2).

#### Goal
Дать исполнителю карточки короткую проверяемую таблицу: по изменённым путям выбрать локальные платформенные
проверки и нужные группы тестов после TEST 2 и TEST 3.

#### Architect Decision
- В `AGENTS.md` добавить раздел «Локальные проверки по изменённым путям». Таблица — читаемое отображение
  `path_keys()` в `tool/ci/scope_guard.sh`, а не новая независимая политика выбора платформ. Порядок правил
  важен: первое совпадение; если изменено несколько файлов, объединить их ключи; `all` раскрыть в реально
  существующие проверки. Указать отдельно, что `scope_guard.sh` сам проверяет ключи префикса ветки и не
  запускает команды.
- Дать команды для `smoke`, `vm`, `windows`, `macos`, `ios`, `android`, `web`, `example` через существующие
  `tool/ci/*`-скрипты. Для ключа `linux` указать действующую CI-проверку: job `linux-native-smoke` в
  `.github/workflows/ci.yml` на `ubuntu-latest`. Она запускается при push в интеграционные ветки из workflow
  или вручную через `workflow_dispatch` с `jobs=linux`; внутри есть Debug/Release CTest, packaging smoke,
  сборка Linux example и app-runtime/native probe через `tool/ci/drive.sh`. Отдельного локального
  Linux runner script нет. Не предлагать включать WSL/Hyper-V.
- В `scope_guard.sh` есть резервные правила для отсутствующих Linux-specific путей. Не включать их в таблицу
  действующих путей. Таблица должна
  покрывать классы действующих путей из `path_keys()`: документация; FFI bindings/headers/config; workflow и
  `tool/ci/*`; `src/**`, IO и функции, `test/probe/**`, `example/integration_test/**`, `pubspec.yaml`;
  Web/WASM; платформенные каталоги; остальной `lib/**`; остальной `test/**` и конфиги анализа/тегов;
  остальной `example/**`; fallback. Для каждого класса указать ключи и команды/условие доступности.
- Рядом с платформенными командами дать селекторы TEST 2 и TEST 3: `smoke || contract`, `probe`, `reference`,
  `release`; для `src/**` — полные затронутые платформенные скрипты по `all`, дополнительно
  `flutter test --tags probe`, `flutter test --tags reference` и native CTest (`cmake -S . -B <temp>
  -DBUILD_TESTING=ON`, сборка и `ctest --test-dir <temp> -C Release --output-on-failure`). Для
  `lib/src/yuv/impl/web/**` — `web` с Web-пробой. Для `lib/src/widgets/**` — ключи `vm example`,
  `contract` и относящиеся к виджету `example/test/**`. Для `*.md` — ключей и запуска нет.
- Не обещать, что платформенный скрипт запускает конкретный тест, если этого нет в его текущем коде;
  выборочные команды приводятся отдельно. Для среза пробы указывать `PROBE_OPS` / `PROBE_FORMATS` и
  проверять строку `PROBE scope`; полный прогон остаётся обязательным, когда его требует карточка.

#### Scope
- Исполнение после завершения TEST 2 и TEST 3: ветка `task/TEST-4` от актуального `dev`, worktree
  `.worktrees/TEST-4`.
- Только раздел в `AGENTS.md` проекта и эта карточка. Таблица ссылается на действующие скрипты и селекторы.

#### Constraints
- Не менять `tool/ci/scope_guard.sh`, другие `tool/ci/*`, workflow, тесты, `lib/`, `src/`, публичный API или ABI.
- Если карта и желаемая проверка расходятся, таблица отражает действующую карту и отдельно называет
  дополнительную выборочную команду; исправление карты — другая задача.
- Linux остаётся проверкой через job `linux-native-smoke` в `.github/workflows/ci.yml`. Ветки задач CI не
  запускают; таблица не объявляет проверку пройденной до результата реального запуска.

#### Definition of Done
- [ ] В `AGENTS.md` есть таблица классов действующих путей из `path_keys()` с первым совпадением,
      объединением ключей и раскрытием `all`; отсутствующие Linux workflow и скрипт не перечислены как
      действующие пути. Для каждого ключа названа реальная команда или явно указано отсутствие локального скрипта.
- [x] Примеры `src/**`, `lib/src/yuv/impl/web/**`, `lib/src/widgets/**`, `*.md` совпадают с действующим
      `scope_guard.sh` и с селекторами TEST 2/TEST 3; native CTest указан отдельно от `tool/ci/*`.
- [x] Linux-ключ ведёт к job `linux-native-smoke` в существующем `.github/workflows/ci.yml`, с условиями
      запуска и фактическим набором проверок; нет ссылок на несуществующие workflow или скрипты как на
      действующие проверки и обещаний о проверках, которых скрипт не выполняет.
- [x] Проверка из Validation выполнена; diff содержит только `AGENTS.md` и эту карточку.

#### Validation
- Сверить каждую строку новой таблицы с `path_keys()` в `tool/ci/scope_guard.sh`, а каждую команду — с
  существующим файлом `tool/ci/*`, селекторами TEST 2 и считыванием среза TEST 3. Особо проверить четыре
  примера из DoD и Linux-строку: `git ls-files .github/workflows tool/ci`, job `linux-native-smoke`, его
  условия запуска и шаги в `.github/workflows/ci.yml`. Отсутствующие пути не включать в таблицу действующих.
- `git diff --check` и `git diff --name-only` в worktree. Это изменение документации; платформенные прогоны
  для самого добавления таблицы не требуются.

#### Executor Report

Свежий Executor T3, GPT-6 Luna, удалил из активной таблицы пути Linux, для которых нет соответствующих
файлов, и указал Linux только через реальный job `linux-native-smoke` в `.github/workflows/ci.yml`.
Сохранены полные пути исполняемых `tool/ci/*` команд, Web `drive.ps1` target/device/arguments и TEST 2/3
селекторы.

Validation:

- `git diff --check` — успешно.
- Все перечисленные в таблице команды и файлы workflow сверены с `git ls-files .github/workflows tool/ci`.
- Linux job, условия запуска и перечисленные шаги сверены с `.github/workflows/ci.yml`.
- Web `drive.ps1` аргументы сверены с `tool/ci/web.ps1`; `gray` и `i420` — с `test/probe/probe_selection.dart`.
- TEST 2 selectors сверены с таблицей в `AGENTS.md`.
- `git diff --name-only` — `AGENTS.md` и `tasks/0.5.0/TEST-4.md`.
- Платформенные проверки не запускались: изменение документационное.

#### Review

**T2 review, GPT-5.6 Terra, 01.10.2026: TODO.**

- Таблица не является точным отображением `path_keys()`: строка `all` сокращает пять путей
  `tool/ci/drive.ps1`, `tool/ci/drive.sh`, `tool/ci/smoke.ps1`, `tool/ci/scope_guard.sh` до
  несуществующих корневых `drive.ps1`, `drive.sh`, `smoke.ps1`, `scope_guard.sh`. Вернуть полные
  пути из `scope_guard.sh`.
- Linux-строка предлагала отсутствующий специализированный workflow; в наличии общий
  `.github/workflows/ci.yml`. Оставить CI-only и назвать существующий путь.
- Описание Web-пробы не даёт исполнимую фактическую команду: `tool/ci/drive.ps1` требует target и
  device. `web.ps1` вызывает его как `integration_test/probe_web_test.dart web-server
  --browser-name=chrome --headless ...`; задокументировать эту форму вместе с
  `--dart-define=PROBE_OPS`/`PROBE_FORMATS` и проверкой `PROBE scope`.
- Validation review: `git diff --check 1eba457..4827327` passed; name-only diff contains only
  `AGENTS.md` and this card. No platform run was required for this documentation-only review.

**T2 review, GPT-5.6 Terra, 01.10.2026: TODO. Reviewed `74144d6`.**

- Не выполнено условие карты о реальных путях: в `AGENTS.md` всё ещё есть строка с отсутствующим
  специализированным Linux workflow. Это также подтверждают перечисление `.github/workflows/` и Executor
  Report. Удалить отсутствующий путь из таблицы.
- Исправления прошлого review подтверждены: пути `tool/ci/drive.ps1`, `tool/ci/drive.sh`,
  `tool/ci/smoke.ps1` и `tool/ci/scope_guard.sh` полные и существуют; Linux описан как CI-only через
  существующий `.github/workflows/ci.yml`.
- Web-команда передаёт обязательные позиционные `Target=integration_test/probe_web_test.dart` и
  `Device=web-server`, далее аргументы Chrome. `drive.ps1` запускает target из `example/`; target существует.
  `gray` является операцией матрицы, `i420` входит в допустимые форматы, а строка `PROBE scope` формируется
  селектором.
- Validation evidence подтверждено: `git diff --check 1eba457..74144d6` прошёл, а name-only diff содержит
  только `AGENTS.md` и эту карточку. Платформенные прогоны не выполнялись: Validation карточки для
  документационного изменения их не требует.

**T2 review, GPT-5.6 Terra, 01.10.2026: TODO. Reviewed `4813dd4`.**

- `AGENTS.md` не покрывает действующий класс `linux/*`: в `tool/ci/scope_guard.sh` он даёт ключ `linux`, а
  `linux/CMakeLists.txt` отслеживается Git. Это нарушает Architect Decision о таблице классов действующих
  путей, включая платформенные каталоги. Добавить строку для существующего `linux/*` с CI-only job
  `linux-native-smoke` в `.github/workflows/ci.yml`; отсутствующие `.github/workflows/ci-linux.yml` и
  `tool/ci/linux.*` не перечислять как действующие.
- Остальные прежние замечания исправлены: отсутствуют `ci-linux.yml` и `tool/ci/linux.*`; все 21 явно
  перечисленный workflow/script путь существует; Linux job и её условия/шаги совпадают с `ci.yml`; Web
  вызов передаёт target, device и Chrome arguments, а `gray`/`i420` и строка `PROBE scope` соответствуют
  селектору.
- Validation review: `git diff --check 1eba457..4813dd4` прошёл; name-only diff содержит только
  `AGENTS.md` и эту карточку. Платформенные прогоны не выполнялись: документационная Validation их не требует.
