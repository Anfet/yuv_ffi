# yuv_ffi 0.5.0 — план релиза

## Цель релиза

- **Цель:** полноценный релиз 0.5.0 — переработанный тест-сьют, база скорости, уборка (устаревшее API, SPM), быстрый показ кадров (геометрия кадра, YUV-шейдер, камерный слой), вставка фрагмента.
- **Рабочая ветка:** `dev`. Релизная ветка `release/0.5.0` ответвляется от `dev` в RELEASE 1 после аудита и повышения версии (D-10).
- **База сравнения:** опубликованная 0.4.0 — `origin/release/0.4.0`.
- **Релиз-кандидат:** не заморожен.
- **Заморозка:** с создания `release/0.5.0`; дальше код меняется только карточками `FIX N`.
- **Тег и публикация:** Engineer.

## Этапы

| Этап | Работа | Выход из этапа |
| --- | --- | --- |
| **1–7. Тест-сьют, скорость, уборка, функциональность, устройство, уборка example, Web и Apple** | завершены | итоги — `COMPLETION.md`; последний полный CI — [`ci/all/WEB-5`](https://github.com/Anfet/yuv_ffi/actions?query=branch%3Aci%2Fall%2FWEB-5) на `6f71a45`, 9/9 |
| **8. Релизный цикл** | FIX 1 → RELEASE 1; FOLLOWUP 1 после гейта | блокирующие находки аудита закрыты; на одном SHA `release/0.5.0` зелёные локальные проверки, `ci/all/0.5.0` и Pixel 3; Engineer подписал |

## Текущее состояние

- **Сейчас:** этапы 1–7 закрыты; FIX 2 и FIX 3 приняты на `4790e9e`. FIX 1 возвращена на доработку: тест покрывает внешнюю реализацию только как источник, а карточка требует проверить внешнего получателя. RELEASE 1 остаётся заблокированной. Версия в `dev` — `0.5.0-dev.1`.
- **Открытые решения Engineer:** см. «Открытые вопросы».

## Пулы задач

Orchestrator записывает для пула порядок карточек, базовый SHA `dev`, уровень Executor и Reviewer и состояние CI. Закрытые пулы из таблицы убираются.

| Пул | Порядок карточек | Tier Executor / Reviewer | База | Внешняя зависимость | CI после слияния |
| --- | --- | --- | --- | --- | --- |
| — | — | — | — | — | — |

## Дашборд

ID ведёт к карточке в `tasks/0.5.0/`.

### Этап 8 — релизный цикл

| ID | Status | Tier | Owner | Depends on | Summary / next step |
| --- | --- | --- | --- | --- | --- |
| [FIX 1](tasks/0.5.0/FIX-1.md) | TODO | T2 / T1 | — | — | **Атомарность `applyPatch()`.** Добавить регрессию с внешним получателем: отказ до записи и успешный путь. Windows и Pixel 3 arm64 на `fec5c9a` прошли. |
| [RELEASE 1](tasks/0.5.0/RELEASE-1.md) | BLOCKED | T2 / T1 + Engineer | — | FIX 1 | **Финальный аудит и релизный гейт 0.5.0.** После принятия FIX 1 дополнить аудит, поднять версию, создать `release/0.5.0` и проверить один SHA: локальные команды, 9 workflow, Pixel 3, `pana`, dry-run. |
| [FOLLOWUP 1](tasks/0.5.0/FOLLOWUP-1.md) | BLOCKED | T2 / T2 | — | RELEASE 1 | **Тест публичной поверхности.** После релизного гейта убрать устаревшее описание deprecated API; выпуск не задерживает. |

Отложено: [RUNNER 1](tasks/0.5.0/RUNNER-1.md) — `DEFERRED` (новые службы раннеров не планируются).

## Открытые вопросы

- **Safari и Firefox для RELEASE 1.** На Mac Safari 18.6, но «Allow Remote Automation» выключен (Safari → Develop или `sudo safaridriver --enable`, нужен пароль); Firefox и `geckodriver` не установлены. Варианты: включить и установить до гейта — или выпустить с записью «не проверено» (как в README и `doc/web-parity.md`). Рекомендация: выпустить с записью — Web заявлен как частичный, проверен Chrome.

## Правила работы

По `D:\.projects\ENGINEERING_PROTOCOL.md` и шаблону `pre-release-todo-template.md`, приведены к работе в `dev`.

0. **Идентификаторы.** В тексте ID карточки пишется словом области и номером через неразрывный пробел: TEST 1; в имени файла — через дефис: `tasks/0.5.0/TEST-1.md`. У пула свой ID — метка CI-тега; старые ветки пулов и задач сохраняют историю.
1. **Этапы по очереди**, внутри этапа — по зависимостям. Заморозка кода — только в этапе 8.
2. **Один пул за раз, прямо в `dev`** (D-25). Orchestrator задаёт порядок карточек по их явным зависимостям. Один Executor выполняет их последовательно в `dev` в основной копии `D:\.projects\yuv_ffi` (без worktree и веток пула, D-22, D-25). На старте Executor записывает в карточку базовый SHA `dev`; нужные проверки печатает `bash tool/ci/scope_guard.sh <base>`. Коммиты можно разделять по карточкам. Следующий пул начинается только после принятия текущего.
3. **Проверка пула — до ревью.** Executor выполняет обязательные проверки каждой карточки и достаточные проверки их общего результата теми же `tool/ci/<платформа>`-скриптами на доступных платформах. Падение теста остаётся его работой. Успешные проверки не повторяются без изменения, которое могло их обесценить. Команды, SHA и результат — в Executor Report карточек; Reviewer проверяет доказательства и требуемые пробы.
   Проверка считается завершённой только после terminal result с exit code и критерием самого скрипта. Частичный stdout, ранний возврат запускающей оболочки или отсутствие exit code — это `RESULT_PENDING`, не `PASS`; Executor ждёт один блокирующий запуск либо фиксирует точную незавершённую команду для Engineer.
   Если Executor не может дождаться запущенного локального tool/run в этой сессии, он **не** оставляет его в фоне и не имитирует ожидание. Он останавливается с отчётом для Engineer: точная команда, cwd, уже известный вывод/состояние, ожидаемый критерий `PASS`/`FAIL` и способ прислать результат. Engineer запускает команду сам и передаёт итог; только после этого Executor продолжает работу.
4. **Принятие и CI** (D-23, D-25): Reviewer проверяет диапазон `<base>..<SHA>` и записывает вердикт с принятым SHA в карточку; доработка — новые коммиты в `dev` поверх. Orchestrator переводит карточки в `DONE` и открывает следующий разрешённый пул. Дополнительный локальный интеграционный прогон после принятия не нужен. Если требуется полный CI, Reviewer или Orchestrator ставит тег `ci/all/<ID-пула>` на точный SHA `dev`; результат сохраняется ссылкой в `COMPLETION.md`, а Watcher ждёт параллельно следующему пулу. Теги `ci/*` удаляются пачкой в конце этапа, запуски при этом остаются. При отказе Orchestrator сам заполняет карточку CI в конце этапа, которому принадлежал упавший пул: SHA, workflow/run/job, упавший шаг, ссылку и короткий фрагмент ошибки. Он сообщает Engineer и не ставит диагноз. Только по следующей команде Engineer отдельный Executor расследует карточку; Architect в обычном маршруте отказа CI не участвует. Выход из этапа/релизный гейт требует зелёного обязательного CI либо явного решения Engineer.
5. **Карточка — отдельный файл** `tasks/0.5.0/<ID>.md`. Executor обновляет карточки пула и сообщает один терминальный итог (`REVIEW`, `BLOCKED`, `AWAITING_EXTERNAL`, `ARCHITECT_REQUIRED`) с коротким доказательством или причиной. Дашборд и таблицу пулов ведёт Orchestrator; внутренний переход между карточками нового агента не запускает. Architect меняет решение и DoD, Executor — раздел `#### Executor Report`. После принятия: одна строка на карточку в `COMPLETION.md` (что сделано, принятый SHA, run CI или pending), карточка удаляется — история остаётся в git.
   Шаблон карточки включает строку `**Probe:** none | windows | windows+pixel3`.
6. **Коммиты статуса — при терминальном переходе пула.** Несколько одновременных переходов карточек пула объединяются в один коммит; внутреннее продвижение Executor не создаёт отдельного коммита дашборда.
7. **Карточки расписаны до запуска.** Перед входом в этап Architect дописывает карточки плановой работы (решение, Scope, DoD, Validation): на дашборде этапа только `TODO` и `BLOCKED`. Фактическую карточку отказа post-merge CI Orchestrator добавляет после отказа со статусом `ENGINEER_REQUIRED`; она не требует Architect и не останавливает следующий пул. `ARCHITECT_REQUIRED` появляется лишь когда исполнение упёрлось в решение; вопрос, который решает Engineer, — `ENGINEER_REQUIRED` с описанием в карточке и строкой в «Открытых вопросах».
8. **Одно ревью готового пула:** ждать произвольного числа готовых карточек не нужно. Reviewer проверяет DoD каждой карточки и общий результат, может исправить небольшие однозначные замечания; существенная переделка получает один полный список блокирующих замечаний. Разрешение Engineer довести этап до `DONE` включает это ревью.
9. **Язык (D-7).** Внешнее — на английском: `README.md`, `CHANGELOG.md`, `example/README.md`, dartdoc и комментарии в коде, комментарии workflow, сообщения коммитов, тексты ошибок. Внутреннее — на русском: `AGENTS.md`, этот план, `COMPLETION.md`, карточки, отчёты, `doc/*.md`. Имена файлов, символов, команд и цитаты из логов не переводятся.
10. **Ограничения Engineer.** WSL/Hyper-V не включать. Native C — по D-17. Тег и публикация — Engineer.

## Статусы

| Статус | Значение / следующий шаг |
| --- | --- |
| `TODO` | Карточка готова к исполнению, когда Engineer разрешит. |
| `IN_PROGRESS` | Один Executor последовательно выполняет карточки пула. |
| `AWAITING_EXTERNAL` | Executor закончил текущую часть; идёт уже запущенный внешний run. Назначить Watcher. |
| `BLOCKED` | Нужное действие или ресурс ещё не в работе; Owner/Summary называет, кто или что разблокирует. Задачи будущих этапов — здесь. |
| `ARCHITECT_REQUIRED` | Исполнение упёрлось в решение или спецификацию: карточку дописывает Architect. |
| `ENGINEER_REQUIRED` | Решение за Engineer: вопрос, варианты и рекомендация — в карточке, строка — в «Открытых вопросах». |
| `REVIEW` | Весь пул готов к ревью, разрешённому целью этапа. |
| `ACCEPTED` | Пул принят Reviewer; принятый SHA — в карточке. |
| `DONE` | Пул принят: убрать карточки из дашборда, записать `COMPLETION.md`, удалить карточки. Состояние CI ведётся отдельно. |
| `DEFERRED` | Отложено Engineer; причина и условие возврата — в карточке, из дашборда убрать. |

## CI и проверки

- **Триггеры (D-23):** автозапуска нет — ни push в `main` и `release/**`, ни push в `dev` CI не запускают. CI ставится тегом `ci/<набор>/<метка>` (набор — `all` или одна платформа) или вручную через `workflow_dispatch`. Перед релизом — `ci/all/<версия>` на SHA `release/<версия>`. Основная проверка — локальные `tool/ci`-скрипты.
- **Локальные команды:** `tool/ci/<платформа>`-скрипты (`vm.ps1`, `windows.ps1`, `android.ps1`, `web.ps1`, `example.ps1`, `smoke.ps1`; на Mac — `macos.sh`, `ios.sh`); ключи по путям — `tool/ci/scope_guard.sh`, команды — `AGENTS.md`.
- **Интеграция:** принятый пул → `DONE`; обязательный CI на принятом SHA `dev` через тег `ci/all/<ID-пула>` и Watcher независимо от работы над следующим пулом (правило 4, D-23, D-25).
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

Действуют и решения цикла 0.4.2:

| ID | Решение |
| --- | --- |
| D-2 | На GitHub-hosted — только Linux-джоба; остальное — self-hosted. |
| D-7 | Язык документов — правило 9 ниже. |
| D-8 | macOS CI использует Bash-скрипты `.sh`; Windows — PowerShell. |
