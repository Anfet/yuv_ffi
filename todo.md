# yuv_ffi 0.5.1 — план релиза

## Цель релиза

- **Цель:** патч 0.5.1 — операции Web backend работают в сборке `flutter build web --wasm` (WEB 4), это проверяет Web CI (CI 1), документация точно описывает статус Web и платформ (FIX 1).
- **Порядок:** код и документация (FIX 1 → WEB 4 → CI 1) → релизный гейт (RELEASE 1) → выпуск Engineer.
- **Рабочая ветка:** `dev`. `release/0.5.1` ответвляется от `dev` в RELEASE 1 на принятом SHA кода (D-10).
- **База сравнения:** опубликованная 0.5.0 — тег `0.5.0` (`3e4c645`).
- **Релиз-кандидат:** не заморожен.
- **Заморозка:** с создания `release/0.5.1`; дальше `lib/`, `src/`, `darwin/`, `android/`, `example/lib/`, `assets/`, `README.md`, `CHANGELOG.md` меняются только карточками `FIX N`.
- **Тег, публикация, `main`:** Engineer (правило 11).

## Этапы

| Этап | Работа | Выход из этапа |
| --- | --- | --- |
| **1. Код и документация** | FIX 1, WEB 4, CI 1 — один пул `WASM` | пул принят Reviewer; на принятом SHA `tool/ci/web.ps1` (JavaScript и `--wasm`) зелёный, проба `windows+pixel3+web` пройдена |
| **2. Релизный гейт** | RELEASE 1 | на одном SHA `release/0.5.1`: проверки по `scope_guard.sh 0.5.0`, `ci/all/0.5.1` 9/9, pana 160/160, dry-run; Engineer подписал |
| **3. Выпуск** | Engineer | тег `0.5.1`, pub.dev, `main` на SHA релиза, `main` влит в `dev` |

## Текущее состояние

- **Выпущено:** 0.5.0 — 05.10.2026, тег `0.5.0` на `3e4c645`; `main` — PR #5 (`c8af6cd`), влит в `dev`.
- **Сейчас:** пул `WASM`: FIX 1 и WEB 4 — `DONE` на `1866a2d`; CI 1 — `BLOCKED`, код принят, ждёт зелёного Web CI (раннер `dev.working` offline).
- **Открытые решения Engineer:** нет.

## Пулы задач

Engineer (или Architect по его команде) записывает для пула порядок карточек, базовый SHA `dev`, уровень Executor и Reviewer и состояние CI. Закрытые пулы из таблицы убираются.

| Пул | Порядок карточек | Tier Executor / Reviewer | База | Внешняя зависимость | CI после принятия |
| --- | --- | --- | --- | --- | --- |
| `WASM` | FIX 1 → WEB 4 → CI 1 | T2 / T1 | SHA `dev` на старте — в карточке FIX 1 | Chrome и ChromeDriver одной major-версии; Pixel 3 (Reviewer) | `ci/web/WASM` на принятом SHA |

## Дашборд

ID ведёт к карточке в `tasks/0.5.1/`.

### Этап 1 — код и документация

| ID | Status | Tier | Owner | Depends on | Summary / next step |
| --- | --- | --- | --- | --- | --- |
| [CI 1](tasks/0.5.1/CI-1.md) | BLOCKED | T3 / T2 | Engineer | — | **Шаг `--wasm` в `tool/ci/web.ps1`.** Код и локальный Web CI на `1866a2d` приняты; run 37243974376 по `ci/web/WASM` упал — раннер `dev.working` потерял связь (offline). Ждёт Engineer: вернуть раннер, перезапустить; при зелёном — `DONE`. |

### Этап 2 — релизный гейт

| ID | Status | Tier | Owner | Depends on | Summary / next step |
| --- | --- | --- | --- | --- | --- |
| [RELEASE 1](tasks/0.5.1/RELEASE-1.md) | BLOCKED | T2 / T1 + Engineer | — | CI 1 | **Релизный гейт 0.5.1.** Аудит разницы с 0.5.0, `release/0.5.1`, проверки на одном SHA, отчёт и команды Engineer. Разблокирует принятие пула `WASM`. |

Отложено: RUNNER 1 — `DEFERRED` (новые службы раннеров не планируются); карточка в git: `git show b160704:tasks/0.5.0/RUNNER-1.md`.

## Открытые вопросы

Нет.

## Правила работы

По `D:\.projects\ENGINEERING_PROTOCOL.md`, файлу своей роли в `D:\.projects\.protocol\` и шаблону `pre-release-todo-template.md`, приведены к работе в `dev`.

0. **Идентификаторы.** В тексте ID карточки пишется словом области и номером через неразрывный пробел: FIX 1; в имени файла — через дефис: `tasks/0.5.1/FIX-1.md`. Номера идут внутри версии; карточка, перенесённая из прошлого цикла, сохраняет ID (WEB 4). У пула свой ID — метка CI-тега.
1. **Этапы по очереди**, внутри этапа — по зависимостям. Заморозка — только в этапе 2.
2. **Один пул за раз, прямо в `dev`** (D-25). Один Executor выполняет карточки пула последовательно в основной копии `D:\.projects\yuv_ffi`, без worktree и веток пула (D-22). На старте Executor записывает в первую карточку базовый SHA `dev`; нужные проверки печатает `bash tool/ci/scope_guard.sh <base>`. Коммиты можно разделять по карточкам.
3. **Проверка пула — до ревью.** Executor выполняет обязательные проверки каждой карточки и общего результата теми же `tool/ci/<платформа>`-скриптами. Падение теста остаётся его работой. Успешные проверки не повторяются без изменения, которое могло их обесценить. Executor Report — `Validated at: <SHA>` и строка на каждый пункт DoD: команда, exit code, счётчик или критерий.
   Проверка завершена только после terminal result с exit code и критерием самого скрипта. Частичный stdout, ранний возврат оболочки или отсутствие exit code — `RESULT_PENDING`, не `PASS`. Если дождаться локального запуска нельзя, Executor не оставляет его в фоне, а останавливается с отчётом для Engineer: команда, cwd, известный вывод, критерий `PASS`/`FAIL`.
4. **Принятие и CI** (D-23, D-25). Reviewer по `D:\.projects\.protocol\reviewer.md` читает диапазон `<base>..<SHA>` и отчёт против карточки, записывает вердикт с принятым SHA; принял — `DONE` (строка в `COMPLETION.md`, строка дашборда убрана, карточка удалена); доработка — новые коммиты в `dev` поверх. CI после принятия — тег `ci/<набор>/<ID-пула>` на точный SHA, результат — ссылкой в `COMPLETION.md`. **Теги `ci/*` — только триггеры:** удаляются пачкой в конце этапа или после выпуска, запуски и ссылки на них остаются в Actions. При отказе CI роль, получившая результат, заполняет факт-карточку (SHA, workflow/run/job, упавший шаг, фрагмент ошибки), сообщает Engineer и не ставит диагноз.
5. **Карточка — отдельный файл** `tasks/0.5.1/<ID>.md`. Architect меняет решение и DoD, Executor — раздел `#### Executor Report`, Reviewer — `#### Review`. Executor ставит `REVIEW` по каждой карточке, как только она готова, не дожидаясь конца пула; ранняя остановка — `BLOCKED`, `ARCHITECT_REQUIRED` или `ENGINEER_REQUIRED` с причиной. После принятия: одна строка на карточку в `COMPLETION.md`, карточка удаляется — история в git.
6. **Статусы, дашборд и коммит — важно и обязательно.** Статус меняет только роль из таблицы «Статусы», в карточке и строке дашборда одним коммитом; дашборд всегда совпадает с карточками. Каждая роль заканчивает работу коммитом своих путей (`git add <пути>`); незакоммиченных файлов после хода не остаётся, чужие незакоммиченные файлы коммит не блокируют и в него не входят.
7. **Карточки расписаны до запуска:** на дашборде этапа только `TODO` и `BLOCKED`. Где предвидится сбой, в Architect Decision — варианты A1/A2… в порядке проверки.
8. **Одно ревью готового пула.** Reviewer проверяет, что каждая карточка сделана так, как в ней написано, чтением diff и отчёта; работу Executor не повторяет. Новых требований не придумывает и не ищет: замеченное по ходу вне карточки — рекомендация Engineer, не причина возврата. Может исправить небольшие однозначные замечания; существенная переделка получает один полный список блокирующих замечаний с критерием закрытия.
9. **Язык (D-7).** Внешнее — на английском: `README.md`, `CHANGELOG.md`, `example/README.md`, `doc/web-parity.md`, dartdoc и комментарии в коде, комментарии workflow, сообщения коммитов, тексты ошибок. Внутреннее — на русском: `AGENTS.md`, этот план, `COMPLETION.md`, карточки, отчёты, прочие `doc/*.md`.
10. **Ограничения Engineer.** WSL/Hyper-V не включать. Native C — по D-17. Тег и публикация — Engineer.
11. **Выпуск.** Тег `<версия>` — аннотированный, без префикса `v`, на SHA `release/<версия>`. `main` переводится на тот же SHA fast-forward (`git push origin <SHA>:main`); merge-коммит в `main` не делается, чтобы `main` оставался предком `dev`. Если `main` всё же разошёлся с `dev`, его сразу вливают в `dev`.

## Статусы — важно и обязательно

Переходы и кто их ставит — `D:\.projects\ENGINEERING_PROTOCOL.md` §3. `ACCEPTED` нет: принятие — это `DONE`.

| Статус | Значение / следующий шаг | Ставит |
| --- | --- | --- |
| `TODO` | Карточка готова к исполнению, когда Engineer разрешит; или возвращена с замечаниями ревью. | Architect, Reviewer |
| `IN_PROGRESS` | Executor выполняет карточку. | Executor |
| `BLOCKED` | Нужное действие, ресурс или внешний результат (CI, устройство) ещё не получен; Owner/Summary называет, кто или что разблокирует. | Executor, Reviewer |
| `ARCHITECT_REQUIRED` | Исполнение упёрлось в решение или спецификацию: карточку дописывает Architect. | Executor |
| `ENGINEER_REQUIRED` | Решение за Engineer: вопрос, варианты и рекомендация — в карточке, строка — в «Открытых вопросах». | Executor, Architect |
| `REVIEW` | Карточка готова и проверена, отчёт заполнен; ждёт ревью. | Executor, по каждой карточке |
| `DONE` | Reviewer принял: строка в `COMPLETION.md`, строка дашборда убрана, карточка удалена. Состояние CI ведётся отдельно. | Reviewer |
| `DEFERRED` | Отложено Engineer; причина и условие возврата — в карточке, из дашборда убрать. | Engineer |

## CI и проверки

- **Триггеры (D-23):** автозапуска нет. CI — тегом `ci/<набор>/<метка>` (набор — `all` или одна платформа) или вручную через `workflow_dispatch`. Перед релизом — `ci/all/<версия>` на SHA `release/<версия>`.
- **Локальные команды:** `tool/ci/<платформа>`-скрипты; ключи по путям — `tool/ci/scope_guard.sh`, команды — `AGENTS.md`.
- **Пробы:** по таблице `AGENTS.md`. Пул `WASM`: FIX 1 (`src/CMakeLists.txt` — номер версии) → `windows+pixel3`, WEB 4 → `web`, CI 1 → `none`; итог пула — `windows+pixel3+web`.
- **Устройство:** Pixel 3 у этой машины; скорость — только release (см. «Окружение»).

## Окружение

### Linux (Ubuntu в VirtualBox)

- Ubuntu 24.04.5 LTS x86_64 — как `ubuntu-latest` в CI (`ubuntu-24.04`); 8 ядер, 11 ГБ, адрес `192.168.1.29`, пользователь `oleg`. Пакеты CI (`clang`, `cmake`, `ninja-build`, `libgtk-3-dev`, `libgstreamer*-dev`, `xvfb`) стоят; `sudo` — с паролем, ставит Engineer.
- Доступ с Windows: `D:\.projects\.tools\linux-runner\linux-run.sh '<команда>'` (ключ `~/.ssh/linux_dev_runner`, адрес — в `host.env` рядом, не в git). Окружение — префиксом: `linux-run.sh "$(cat D:/.projects/.tools/linux-runner/linux-env.sh) && flutter --version"`.
- Flutter 3.44.9 — `~/storage/flutter_3.44/flutter` (shallow clone, `flutter doctor` ругается на канал — не мешает).
- Синхронизация — tar через SSH в `~/claude-work/yuv_ffi`: `git -c core.autocrlf=false archive --format=tar <ref> | ssh … 'tar -xf - -C ~/claude-work/yuv_ffi'`. **Без `core.autocrlf=false` скрипты приезжают с CRLF**, и `bash tool/ci/*.sh` падает на `$'
'`.
- Проверки — как в джобе `linux-native-smoke`: в `example/` `flutter create --platforms=linux .`, затем `xvfb-run -a bash tool/ci/drive.sh integration_test/<target> linux`.
- Раннер `linux-vmbox` — служба systemd от `oleg` (`~/actions-runner`, `sudo ./svc.sh status`), поднимается с VM; workflow на неё не направлены (D-26).
- WSL/Hyper-V по-прежнему не включать; VirtualBox и эмулятор Android могут конфликтовать за виртуализацию — запускать по очереди.

### Windows (эта машина; она же self-hosted раннер `dev.working`)

- Flutter 3.44.9: `D:\.important\flutter-3.44\flutter`.
- Android SDK `D:\.important\android-sdk` (NDK 21…28, cmake 3.18.1 / 3.22.1 / 4.1.2), JDK `D:\.important\jdk-17.0.12`, AVD `Tablet` (API 35 x86_64). Android-сборки делать локально, не в CI.
- cmake для native: `D:\.important\android-sdk\cmake\3.22.1\bin` (им пользуются `tool/ci/*.ps1`) или cmake из Visual Studio 2022.
- Git Bash `D:\.important\Git\bin\bash.exe`; emsdk 3.1.74 в `D:\.projects\.tools\emsdk-3.1.74` (глобальный 5.0.1 не использовать). Сборка WASM — `bash ./tool/wasm/build_wasm.sh`, не `sh`.
- **Pixel 3** (`8B1X11QLW`) подключён к этой машине по USB: `adb` из `D:\.important\android-sdk\platform-tools`. Скорость — только в release: `flutter build apk --release -t <entry>`, `adb install -r`, `adb shell am start`, результат из `adb logcat`. `flutter drive` release не поддерживает, а profile завышает FFI в 3–6 раз.

### ChromeDriver

- **Windows:** `D:\.projects\.tools\chromedriver-win64\chromedriver.exe`, Chrome 154. Web CI запускает его сам через `tool/ci/web.ps1` (порт 4444) и падает, если major-версии Chrome и драйвера разные.
- **Обновление Chrome ломает драйвер молча.** Симптом: `flutter drive` доходит до `Debug service listening on ws://…`, и лог больше не растёт. Сверить `chrome --version` и `chromedriver --version`; драйвер брать из Chrome for Testing точно под major Chrome (`https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_<major>`).
- Перед запуском убивать старый драйвер, иначе порт 4444 занят прежней версией (`bind() failed: Address already in use`).
- `flutter drive` возвращает exit 0 и при провале: судить только по строке `All tests passed` (так делает `tool/ci/drive.ps1`), прогон подтверждать негативным контролем.
- Если ручной `flutter test --platform chrome` на Windows висит на `loading <test>.dart`, запускать на Mac.
- `flutter test --platform chrome` не отдаёт asset bundle, поэтому тесты с ассетами (WASM-модуль, эталонные PNG) в браузере запускаются только через `flutter drive`.

### Mac (self-hosted раннер `yuv-self-hosted`)

- Доступ с Windows: `D:\.projects\.tools\mac-runner\mac-run.sh '<команда>'`. Адрес и пользователь — в `host.env` рядом (не в git).
- SSH-сессия неинтерактивная и не читает `~/.zshrc`: каждую команду начинать с окружения —
  `mac-run.sh "$(cat D:/.projects/.tools/mac-runner/mac-env.sh) && flutter --version"`. Без него `flutter`, `pod` и rbenv «не найдены», хотя установлены.
- Flutter — `~/storage/flutter_3.44/flutter` (рядом есть 3.38.7 и 3.41.9); Android SDK — `~/storage/android/sdk`; cmake — `~/storage/android/sdk/cmake/<версия>/bin/cmake` (отдельно не установлен); CocoaPods — gem в `~/.gem/bin`, не Homebrew.
- Копирование рабочего дерева: `rsync` на Windows нет, `mac-sync-run.sh` не работает. Собрать tar (`git archive --format=tar HEAD`, при необходимости дописать изменённые файлы) и распаковать на Mac через `ssh … 'tar -xf - -C ~/claude-work/<проект>'`.
- CI-скрипты macOS/iOS — Bash (`tool/ci/macos.sh`, `tool/ci/ios.sh`, D-8).
- **Release-сборки с Flutter 3.44 на этом Mac раньше виснули (04.10 по SSH прошла за ~40 с, не воспроизвелось):** `gen_snapshot` стоит в `_dyld_start` с нулевым CPU (Gatekeeper, лечится только root). Для проверок поведения собирать debug; на CI не влияет.
- Браузерные прогоны: `export CHROME_EXECUTABLE='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'`, драйвер `~/bin/chromedriver` (`export PATH="$HOME/bin:$PATH"`, `pkill -f chromedriver`, затем `chromedriver --port=4444` в фоне). Драйвер под mac-arm64 из Chrome for Testing, после установки снять карантин `xattr -d com.apple.quarantine ~/bin/chromedriver`.
- Safari 18.6 (macOS 15.6.1): «Allow Remote Automation» выключен, `safaridriver --enable` по SSH не проходит sudo. Firefox и `geckodriver` не установлены.

## Решения Engineer

| ID | Дата | Решение |
| --- | --- | --- |
| D-10 | 30.09.2026 | 0.4.2 не выпускается: её код слит в `dev` как проверенная точка (01.10.2026). Работа 0.5.0 ведётся прямо в `dev`; при готовности от `dev` ответвляется `release/0.5.0`, и релизный цикл идёт там по схеме 0.4.2. |
| D-13 | 30.09.2026 | Камерный слой остаётся в `example/`, но собирается в `example/lib/camera/` так, чтобы его можно было вынести в отдельный плагин переносом папки и её тестов. |
| D-14 | 30.09.2026 | Версии в `dev`: `0.5.0-dev.N`; при выпуске — `0.5.0`. Номер везде один: `pubspec.yaml`, `CHANGELOG.md`, `darwin/yuv_ffi.podspec` (до слияния SPM 1 — `ios|macos/*.podspec`), `src/CMakeLists.txt`. |
| D-17 | 01.10.2026 | Native C (`src/`) меняется только как работа задачи: изменение явно описано в Architect Decision карточки (что и зачем) или сама задача — native-изменение с известным решением. Пробные, экспериментальные и временные правки `src/` ради тестов и проверок не делаются. Одобренная Engineer карточка — это и есть разрешение. |
| D-19 | 02.10.2026 | `zoom`, `focus` и `crop` геометрии кадра (план GEOM 1) перенесены до появления потребителя: на этапе 4 их никто не использует. Зум превью — `CameraController.setZoomLevel()`, часть кадра на экране — `cover` + `alignment`, вырезание данных — `cropped()`/`applyCrop()`. |
| D-23 | 02.10.2026 | CI без автозапуска: все workflow, включая Linux, запускаются только тегом `ci/<набор>/<метка>` или вручную. Push в `main` и `release/**` CI не запускает; перед релизом — тег `ci/all/<версия>` на SHA `release/<версия>`. Self-hosted workflow не удаляются. |
| D-22 | 02.10.2026 | Git worktree не используются: работа идёт последовательно в основной копии (ветки — D-25). Вместо `PROTOCOL.md` действует `ENGINEERING_PROTOCOL.md`. |
| D-24 | 03.10.2026 | Минимум пакета — Dart 3.12 / Flutter 3.44 (было 3.10 / 3.38): на 3.44 идёт вся работа и все прогоны; более старые версии не тестируются (example требует Dart 3.11 из-за `camera_desktop`), стабильная линия — уже 3.47. `setImageSampler` получает явный `filterQuality: FilterQuality.none`. |
| D-26 | 04.10.2026 | Linux VM (`linux-vmbox`) — self-hosted раннер как служба systemd (`actions.runner.Anfet-yuv_ffi.linux-vmbox.service`), но workflow на неё не направляются: Linux-задание `ci.yml` остаётся на `ubuntu-latest`, потому что VirtualBox и Android-эмулятор на Windows-машине спорят за виртуализацию, а `ci/all` запускает Android параллельно. VM — для ручных прогонов, когда эмулятор не нужен. |
| D-25 | 03.10.2026 | Пока пулы не идут параллельно, отдельных веток нет: пул работает прямо в `dev`, база ревью — SHA `dev` на старте пула, записанный в карточке; доработка — новые коммиты поверх. `scope_guard.sh <base>` печатает нужные ключи проверок вместо проверки префикса ветки. |
| D-27 | 04.10.2026 | Safari и Firefox в 0.5.0 не проверяются: README, `doc/web-parity.md` и отчёт RELEASE 1 пишут «not verified». Web заявлен как частичный, проверен Chrome. |
| D-30 | 05.10.2026 | 0.5.1 — FIX 1 (документация Web и платформ) и WEB 4 (`--wasm`). Решение D-29 (патч только документации, WEB 4 — в 0.5.2) отменено. Проверка `--wasm` в Web CI (CI 1) и релизный гейт (RELEASE 1) — декомпозиция Architect. Версия сразу `0.5.1` (без `-dev.N`), её ставит FIX 1. Safari и Firefox — по D-27. |

Действуют и решения цикла 0.4.2:

| ID | Решение |
| --- | --- |
| D-2 | На GitHub-hosted — только Linux-джоба; остальное — self-hosted. |
| D-7 | Язык документов — правило 9 выше. |
| D-8 | macOS CI использует Bash-скрипты `.sh`; Windows — PowerShell. |
