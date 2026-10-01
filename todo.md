# yuv_ffi 0.5.0 — план релиза

## Цель релиза

- **Цель:** полноценный релиз 0.5.0 — переработанный тест-сьют, база скорости, уборка (устаревшее API, SPM), быстрый показ кадров (геометрия кадра, YUV-шейдер, камерный слой), вставка фрагмента.
- **Порядок:** тест-сьют → скорость → уборка → функциональность → проверка на устройстве → релизный цикл.
- **Рабочая ветка:** `dev`. Релизная ветка `release/0.5.0` ответвляется от `dev` только на этапе 6 (D-10).
- **Релиз-кандидат:** не заморожен.
- **Заморозка:** только на этапе 6.
- **Тег и публикация:** Engineer.

## Этапы

| Этап | Работа | Выход из этапа |
| --- | --- | --- |
| **1. Тест-сьют** | TEST 1…7 | теги работают, эталон сверен с libyuv, дубли убраны, вывод тихий |
| **2. Пробы и скорость** | PROBE 1, PROBE 2, RUNNER 1 | базовые линии 0.4.0 и `dev` сняты в release; правило проб в `AGENTS.md` |
| **3. Уборка** | CLEAN 1, CLEAN 2, SPM 1 | в example нет стендов прошлых замеров; устаревшего API нет; SPM собирается |
| **4. Функциональность** | GEOM 1, PATCH 1, SHADER 1, PRESENT 1, CAMERA 1, CAMERA 2 | всё принято и влито в `dev` |
| **5. Проверка на устройстве** | DEVICE 1 | Pixel 3 в release: FPS, рамки лиц, «снимок = видимое» |
| **6. Релизный цикл** | RELEASE 1 (карточка — при старте этапа) | финальный гейт пройден, Engineer подписал |
| **Параллельно** | WEB 1, WEB 2 | не блокируют этапы |

## Текущее состояние

- **Сделано:** цикл 0.4.2 закрыт без выпуска, его код — проверенная точка в `dev` (`COMPLETION.md`).
- **Сейчас:** этап 1. TEST 1 и TEST 2 завершены (`da55e06`, `5fdcb3c`); TEST 3 и TEST 6 возвращены в работу по замечаниям ревью, TEST 7 принята. TEST 4 ждёт принятия TEST 3; TEST 5 готова к запуску.
- **Открытые решения Engineer:** см. «Открытые вопросы».

## Дашборд

ID ведёт к карточке в `tasks/0.5.0/`. Карточки текущего этапа расписаны Architect-ом до запуска: `TODO` или `BLOCKED` по зависимостям. Задачи будущих этапов — черновики (только Goal) в `BLOCKED`; Architect дописывает их при входе в этап.

### Этап 1 — тест-сьют

| ID | Status | Tier | Owner | Depends on | Summary / next step |
| --- | --- | --- | --- | --- | --- |
| [TEST 3](tasks/0.5.0/TEST-3.md) | TODO | T2 | Terra | TEST 2 | **Срезы проб по операции и формату.** Review `8be229e` требует отклонять явный `all`, проверять полный golden ID-набор до фильтрации во всех трёх targets и записать Web охват с точной drive-командой. |
| [TEST 4](tasks/0.5.0/TEST-4.md) | BLOCKED | T3 | TEST 2/3 | TEST 2, TEST 3 | **Карта «что изменил → что запускать».** Было RA-62. Ждёт TEST 2 и TEST 3. |
| [TEST 5](tasks/0.5.0/TEST-5.md) | TODO | T2 | — | TEST 1, TEST 2, TEST 7 | **Чистка дублирующих тестов.** Все зависимости приняты/завершены; можно запускать. Сохранять доказательство мутацией, `src/` не менять (D-17). |
| [TEST 6](tasks/0.5.0/TEST-6.md) | TODO | T3 | Luna | TEST 2 | **Тихий вывод тестов и CI.** Review `8cf0ebd`: при общем падении успешные наборы всё ещё печатаются как `Passed`; исправить поведение по Architect Decision и добавить регрессионную проверку. |
| [TEST 7](tasks/0.5.0/TEST-7.md) | ACCEPTED | T2 | Reviewer | — | **Сверка эталона с libyuv.** Review подтвердил Mac normal/negative-control, Windows dry-run и ограничения Y/U/V, BGRA относительно `i420_decode` на `03b1bd1`. |

### Этап 2 — пробы и скорость

| ID | Status | Tier | Owner | Depends on | Summary / next step |
| --- | --- | --- | --- | --- | --- |
| [PROBE 1](tasks/0.5.0/PROBE-1.md) | BLOCKED | T2 | этап 1 | TEST 3 | **Базовые линии скорости 0.4.0 против `dev`.** Было RA-26. Pixel 3 — только release-раннер, не `flutter drive --profile`. Ждёт этапа 2. |
| [PROBE 2](tasks/0.5.0/PROBE-2.md) | BLOCKED | T3 | PROBE 1 | PROBE 1, TEST 4 | **Правило проб для задач.** Было RA-27. Поле `Probe` в карточке и правило в `AGENTS.md`. |
| [RUNNER 1](tasks/0.5.0/RUNNER-1.md) | BLOCKED | T2 | Engineer | — | **Дополнительные self-hosted раннеры.** Было RA-80. Ждёт прав администратора Windows для службы раннера. |

### Этап 3 — уборка

| ID | Status | Tier | Owner | Depends on | Summary / next step |
| --- | --- | --- | --- | --- | --- |
| [CLEAN 1](tasks/0.5.0/CLEAN-1.md) | BLOCKED | T3 | этап 2 | — | **Убрать следы замеров из example.** Экран PACK-00, хуки VIEW-03, переключатель упаковки. |
| [CLEAN 2](tasks/0.5.0/CLEAN-2.md) | BLOCKED | T2 | этап 2 | TEST 2 | **Удалить устаревшее API** (D-11) вместе с его тестами; миграция в README и CHANGELOG. |
| [SPM 1](tasks/0.5.0/SPM-1.md) | BLOCKED | T1 | этап 2 | — | **Swift Package Manager для iOS/macOS** (D-12). Сначала план переноса native-исходников на одобрение Engineer. |

### Этап 4 — функциональность

| ID | Status | Tier | Owner | Depends on | Summary / next step |
| --- | --- | --- | --- | --- | --- |
| [GEOM 1](tasks/0.5.0/GEOM-1.md) | BLOCKED | T1 | этап 3 | CLEAN 2 | **Геометрия кадра `FrameGeometry`.** Ориентация, вписывание, зум, обрезка кадра по видимой области; рамки и оверлеи из одного источника. |
| [PATCH 1](tasks/0.5.0/PATCH-1.md) | BLOCKED | T2 | этап 3 | GEOM 1 | **Вставка фрагмента в изображение.** Было PATCH-00 (план 0.4.3). Общее с GEOM 1 правило выравнивания 2×2. |
| [SHADER 1](tasks/0.5.0/SHADER-1.md) | BLOCKED | T1 | этап 3 | GEOM 1 | **YUV-шейдер в пакете.** По прототипу VIEW-04; проверка «шейдер против CPU» — операцией пробы на всех платформах. |
| [PRESENT 1](tasks/0.5.0/PRESENT-1.md) | BLOCKED | T2 | этап 3 | GEOM 1, SHADER 1 | **Режимы показа кадров в презентере.** Ориентация при рисовании и шейдерный путь; только добавления в API. |
| [CAMERA 1](tasks/0.5.0/CAMERA-1.md) | BLOCKED | T2 | этап 3 | CLEAN 1, PRESENT 1 | **Источник кадров камеры в example** (D-13). Одна логика потока, `CameraFrame` с ленивым `upright()`. |
| [CAMERA 2](tasks/0.5.0/CAMERA-2.md) | BLOCKED | T2 | этап 3 | CAMERA 1 | **Виджеты камеры в example.** `YuvCameraView` и `YuvTransformView`; `CameraScreen` на новом API. |

### Этап 5 — проверка на устройстве

| ID | Status | Tier | Owner | Depends on | Summary / next step |
| --- | --- | --- | --- | --- | --- |
| [DEVICE 1](tasks/0.5.0/DEVICE-1.md) | BLOCKED | T2 | этап 4 | CAMERA 2 | **Проверка на Pixel 3.** Release: FPS превью при фоновой обработке, рамки лиц, «снимок = видимое», повтор стенда VIEW-04. |

### Параллельно

| ID | Status | Tier | Owner | Depends on | Summary / next step |
| --- | --- | --- | --- | --- | --- |
| [WEB 1](tasks/0.5.0/WEB-1.md) | BLOCKED | T1 | SHADER 1 | SHADER 1 | **Веб: кадры камеры в YUV без RGBA.** Исследование `VideoFrame.copyTo()` в I420/NV12 и шейдера на вебе. |
| [WEB 2](tasks/0.5.0/WEB-2.md) | BLOCKED | T2 | Engineer | — | **Веб: паритет WASM с native.** Было WAIT-01. Черновик: старт — по решению Engineer, до постановки Architect дописывает карточку. |

## Открытые вопросы



## Правила работы

По `D:\.projects\PROTOCOL.md` и шаблону `pre-release-todo-template.md`, приведены к работе в `dev`.

0. **Идентификаторы.** В тексте ID пишется словом области и номером через неразрывный пробел: TEST 1. В имени файла карточки, ветки и worktree — через дефис: `tasks/0.5.0/TEST-1.md`, `task/TEST-1`, `.worktrees/TEST-1`.
1. **Этапы по очереди**, внутри этапа — по зависимостям. Заморозка кода — только в этапе 6.
2. **Одна карточка — одна ветка** `task/<ID>` от `dev`, при параллельной работе — свой worktree `.worktrees/<ID>`. Карточка, которая меняет сами workflow или `tool/ci/*` и не проверяется локально, берёт ветку `ci/<ID>`: она запускает полный CI (D-9). В коммит — только файлы своей карточки. Основная рабочая копия `D:\.projects\yuv_ffi` — не место для незакоммиченной работы.
3. **Проверка карточки — локальная.** Исполнитель запускает те же `tool/ci/<платформа>`-скрипты, что и CI, для затронутых платформ (карта путей — `tool/ci/scope_guard.sh`, после TEST 4 — таблица в `AGENTS.md`): Windows и Android — локально, macOS и iOS — на Mac через mac-runner. Логи — в Executor Report. Ревьюер перепроверяет выборочно.
4. **Полный CI — один раз на пачку** (D-16): принятые карточки собираются в `ci/<пачка>` от `dev`, зелёная пачка сливается в `dev`. Прогоны не отменяются; красный — виновника ищут локальными прогонами по карточкам пачки, карточка уходит в `REWORK`.
5. **Карточка — отдельный файл** `tasks/0.5.0/<ID>.md`. Исполнитель обновляет свою карточку и сообщает терминальный статус (`REVIEW`, `BLOCKED`, `AWAITING_EXTERNAL`, `ARCHITECT_REQUIRED`) с коротким доказательством или причиной. Дашборд в этом файле ведёт Orchestrator: переносит каждый переход до запуска следующей работы (PROTOCOL.md, «Dashboard ownership»). Архитектор меняет решение и DoD, исполнитель — раздел `#### Executor Report`. Принятая карточка: одна строка в `COMPLETION.md` (что сделано, SHA слияния, run CI), файл карточки удаляется — история остаётся в git.
6. **Коммиты статуса — только при смене статуса карточки.**
7. **Карточки расписаны до запуска.** Перед входом в этап Architect дописывает все его карточки (решение, Scope, DoD, Validation): на дашборде этапа только `TODO` и `BLOCKED`. `ARCHITECT_REQUIRED` появляется лишь когда исполнение упёрлось в решение; вопрос, который решает Engineer, — `ENGINEER_REQUIRED` с описанием в карточке и строкой в «Открытых вопросах». Такая карточка не останавливает остальные.
8. **Пакетное ревью:** при 2–4 готовых карточках — один пакетный вызов ревьюера; каждая карточка проверяется по своему DoD.
9. **Язык (D-7).** Внешнее — на английском: `README.md`, `CHANGELOG.md`, `example/README.md`, dartdoc и комментарии в коде, комментарии workflow, сообщения коммитов, тексты ошибок. Внутреннее — на русском: `AGENTS.md`, этот план, `COMPLETION.md`, карточки, отчёты, `doc/*.md`. Имена файлов, символов, команд и цитаты из логов не переводятся.
10. **Ограничения Engineer.** `tool/bench/` не трогать и не коммитить. WSL/Hyper-V не включать. Native C — по D-17. Тег и публикация — Engineer.

## Статусы

| Статус | Значение / следующий шаг |
| --- | --- |
| `TODO` | Карточка готова к исполнению, когда Engineer разрешит. |
| `IN_PROGRESS` | Работает свежий Executor. |
| `AWAITING_EXTERNAL` | Executor закончил текущую часть; идёт уже запущенный внешний run. Назначить Watcher. |
| `BLOCKED` | Нужное действие или ресурс ещё не в работе; Owner/Summary называет, кто или что разблокирует. Задачи будущих этапов — здесь. |
| `ARCHITECT_REQUIRED` | Исполнение упёрлось в решение или спецификацию: карточку дописывает Architect. |
| `ENGINEER_REQUIRED` | Решение за Engineer: вопрос, варианты и рекомендация — в карточке, строка — в «Открытых вопросах». |
| `REVIEW` | Исполнение закончено; ревью — только по разрешению Engineer. |
| `ACCEPTED` | Независимое ревью пройдено; готово к интеграции пачкой. |
| `DONE` | Влито, общая проверка пройдена: убрать из дашборда, строка в `COMPLETION.md`, карточка удаляется. |
| `DEFERRED` | Отложено Engineer; причина и условие возврата — в карточке, из дашборда убрать. |

## CI и проверки

- **Триггеры (D-9):** полный CI — только `release/**`, `main` и `ci/**`; `dev` и `task/*` CI не запускают; документы CI не запускают.
- **Локальные команды:** `tool/ci/<платформа>`-скрипты (`vm.ps1`, `windows.ps1`, `android.ps1`, `web.ps1`, `example.ps1`, `smoke.ps1`; на Mac — `macos.sh`, `ios.sh`). После TEST 2 — выбор тестов тегами, после TEST 4 — таблица «путь → команды» в `AGENTS.md`.
- **Интеграция:** пачка принятых карточек → `ci/<пачка>` от `dev` → полный CI → слияние в `dev` (правило 4, D-16).
- **Устройство:** Pixel 3 у этой машины; скорость — только release (см. «Окружение»).

## Окружение

### Linux

**Локальной Linux-машины нет.** WSL/Hyper-V не включать. Linux проверяется только GitHub-hosted джобой CI (D-2);
задачи, которым нужна локальная проверка на Linux, откладываются или решаются через CI.

### Windows (эта машина; она же self-hosted раннер `dev.working`)

- Flutter 3.44.9: `D:\.important\flutter-3.44\flutter`.
- Android SDK `D:\.important\android-sdk` (NDK 21…28, cmake 3.18.1 / 3.22.1 / 4.1.2), JDK `D:\.important\jdk-17.0.12`, AVD `Tablet` (API 35 x86_64). Android-сборки делать локально, не в CI.
- cmake для native: `D:\.important\android-sdk\cmake\3.22.1\bin` (им пользуются `tool/ci/*.ps1`) или cmake из Visual Studio 2022.
- Git Bash `D:\.important\Git\bin\bash.exe`; emsdk 3.1.74 в `D:\.projects\.tools\emsdk-3.1.74` (глобальный 5.0.1 не использовать). Сборка WASM — `bash ./tool/wasm/build_wasm.sh`, не `sh`.
- **Pixel 3** (`8B1X11QLW`) подключён к этой машине по USB: `adb` из `D:\.important\android-sdk\platform-tools`. Скорость — только в release: `flutter build apk --release -t <entry>`, `adb install -r`, `adb shell am start`, результат из `adb logcat`. `flutter drive` release не поддерживает, а profile завышает FFI в 3–6 раз.

### ChromeDriver

- **Windows:** `D:\.projects\.tools\chromedriver-win64\chromedriver.exe`, Chrome 154.0.8037.58. Web CI запускает его сам через `tool/ci/web.ps1` (порт 4444) и падает, если major-версии Chrome и драйвера разные.
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
- **Release-сборки с Flutter 3.44 на этом Mac виснут:** `gen_snapshot` стоит в `_dyld_start` с нулевым CPU (Gatekeeper, лечится только root). Для проверок поведения собирать debug; на CI не влияет.
- Браузерные прогоны: `export CHROME_EXECUTABLE='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'`, драйвер `~/bin/chromedriver` (`export PATH="$HOME/bin:$PATH"`, `pkill -f chromedriver`, затем `chromedriver --port=4444` в фоне). Драйвер под mac-arm64 из Chrome for Testing, после установки снять карантин `xattr -d com.apple.quarantine ~/bin/chromedriver`.

## Решения Engineer

| ID | Дата | Решение |
| --- | --- | --- |
| D-10 | 30.09.2026 | 0.4.2 не выпускается: её код слит в `dev` как проверенная точка (01.10.2026). Работа 0.5.0 ведётся прямо в `dev`; при готовности от `dev` ответвляется `release/0.5.0`, и релизный цикл идёт там по схеме 0.4.2. |
| D-11 | 30.09.2026 | Устаревшее (`@Deprecated`) API удаляется в 0.5.0 вместе с его тестами. |
| D-12 | 30.09.2026 | Поддержка Swift Package Manager для iOS/macOS входит в 0.5.0. Затрагивает раскладку native-исходников: план и отдельное одобрение Engineer до начала работ (AGENTS.md, «Native C code»). |
| D-13 | 30.09.2026 | Камерный слой остаётся в `example/`, но собирается в `example/lib/camera/` так, чтобы его можно было вынести в отдельный плагин переносом папки и её тестов. |
| D-14 | 30.09.2026 | Версии в `dev`: `0.5.0-dev.N`; при выпуске — `0.5.0`. Номер везде один: `pubspec.yaml`, `CHANGELOG.md`, `ios|macos/*.podspec`, `src/CMakeLists.txt`. |
| D-17 | 01.10.2026 | Native C (`src/`) меняется только как работа задачи: изменение явно описано в Architect Decision карточки (что и зачем) или сама задача — native-изменение с известным решением. Пробные, экспериментальные и временные правки `src/` ради тестов и проверок не делаются. Одобренная Engineer карточка — это и есть разрешение. |
| D-16 | 01.10.2026 | Полный CI для работы в `dev` — пачками, без правки workflow: принятые карточки сливаются в ветку `ci/<пачка>` от `dev`, её push запускает полный CI (`ci/**` — триггер D-9); зелёная пачка сливается в `dev`, карточки получают `DONE`. Красная — виновник ищется локальными прогонами, его карточка уходит на доработку, остальные повторяют пачку. `dev` в триггеры не добавляется. |
| D-15 | 01.10.2026 | 0.4.2 не публикуется, поэтому её записи в `CHANGELOG.md` объединяются с записью 0.5.0: одна запись с миграцией от 0.4.0 / 0.2.4. Делается при первом повышении версии до `0.5.0-dev.1`. |

Действуют и решения цикла 0.4.2:

| ID | Решение |
| --- | --- |
| D-2 | На GitHub-hosted — только Linux-джоба; остальное — self-hosted. |
| D-7 | Язык документов — правило 9 ниже. |
| D-8 | macOS CI использует Bash-скрипты `.sh`; Windows — PowerShell. |
| D-9 | CI запускается только на `release/**`, `main` и `ci/**`; документы (`*.md`, `doc/**`, `tasks/**`) CI не запускают. Поэтому push в `dev` и в ветки задач CI не запускает. |

## Основание для этапа 4

Исследование VIEW-04 ([`doc/view04-yuv-shader.md`](doc/view04-yuv-shader.md), стенды `example/lib/view04_*.dart`):
Pixel 3, release, живая фронтальная камера 720×480 — текущий путь показывает 20,4–21,1 из 30 кадров/с (~22 мс на
кадр), прототип шейдера — 29,8–29,9 (~6,5 мс); выход шейдера совпадает с CPU-путём попиксельно.

## Завершение

Задача в `DONE`: одна строка в `COMPLETION.md` (что сделано, SHA слияния, run CI), карточка удаляется — история в git.
