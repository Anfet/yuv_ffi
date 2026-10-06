# FIX 1 — Согласовать документацию перед релизом 0.5.1
**Status:** REVIEW · **Tier:** T2, Reviewer T1 · **Owner:** Reviewer · **Depends On:** — · **Probe:** none

**Base SHA:** `0ae4149448f41dfcb28c73ef35f76397eb5c6ae8`

Повторно открыта по команде Engineer 07.10.2026 после релизного аудита. Первоначальная приёмка FIX 1 отражена в
`COMPLETION.md` и git; это продолжение той же задачи. При следующем закрытии Reviewer обновляет существующую
строку FIX 1 в `COMPLETION.md`, сохраняя факт первоначальной приёмки, а не добавляет вторую строку с тем же ID.

#### Goal

Четыре внешних документа одинаково описывают 0.5.1: исправление Web `--wasm`, проверенные границы поддержки и
переход с 0.2.4/0.4.0 либо 0.5.0. Один Executor выполняет шаги последовательно в `dev`, без делегирования.
После приёмки RELEASE 1 сможет собрать новый кандидат с этими правками и проверить его.

#### Diagnosis

- `MIGRATION.md`, раздел Native and Web consumers, описывает падение `--wasm` как текущее ограничение. В 0.5.1
  оно исправлено; руководство рекомендует `^0.5.0`, которое также допускает 0.5.1.
- `example/README.md` без оговорок заявляет отсутствие паритета Web с native, тогда как README пакета и
  `doc/web-parity.md` подтверждают совпадение операций в проверенных случаях на JavaScript и `--wasm` в Chrome.
- Публичные API и общие типы между 0.5.0 и кандидатом `61da2ee` не менялись. Патч не требует новых замен API.
- RELEASE 1 и `todo.md` уже уточнены Architect: задача зависит от этой приёмки, старый PASS — история старого SHA.

#### Architect Decision

1. **Начать в основной копии `dev`.** Проверить `git status --short`; чужие изменения сохранить. На старте записать
   базовый SHA `dev` в эту карточку. Прочитать нужные разделы четырёх документов Scope, `pubspec.yaml` и
   `doc/web-parity.md` (Current Flutter-WASM verification, Other public paths, 0.5.1 verification).
2. **MIGRATION — сохранить правила миграции API, обновить область применения.**
   - Заголовок и Scope: переход с 0.2.4 или retracted 0.4.0 на линию 0.5.x, включая 0.5.1; SDK/platform minimums
     оставить прежними. В Steps рекомендовать `yuv_ffi: ^0.5.1` и `flutter pub upgrade yuv_ffi`.
   - Добавить короткий раздел `Updating from 0.5.0 to 0.5.1`: обязательных замен API и повторной миграции
     сериализованных кадров нет; обновить зависимость, выполнить upgrade, проверить приложение на его targets.
   - В таблице обозначить новый API как 0.5.x. Все существующие rename/review-правила, NV12 UV order, layouts,
     initialization и Stored frames сохранить по смыслу. Упоминания 0.5.0 как версии введения изменений допустимы.
   - В Native and Web consumers: обе Flutter-сборки работают в проверенных случаях Chrome; прежний interop-сбой
     относится к 0.5.0 и исправлен в 0.5.1. Safari/Firefox — not verified. Не обещать поддержку всех входов/браузеров.
3. **README примера — согласовать Web.** Заменить общее утверждение об отсутствии паритета на те же границы:
   JavaScript и `--wasm`, проверенные операции в Chrome, Safari/Firefox not verified. Сохранить команду запуска
   примера, ограничения камеры и список включённых runners. Поддержка камеры не выводится из паритета операций.
4. **README пакета и CHANGELOG.**
   - README: заголовок миграции — `Migrating to 0.5.x`; ссылка на MIGRATION и краткое пояснение, что 0.5.0 → 0.5.1
     не требует замен API. Requirements, Platform status и Web backend сверить с обновлёнными документами.
   - Только в верхней записи CHANGELOG `## 0.5.1` дополнить Documentation: руководство миграции и README примера
     согласованы с поддержкой 0.5.1. Исторические записи, включая Known limitations 0.5.0, оставить историей.
5. **Проверить, затем отделить коммит пакета от статуса.** Выполнить Validation; исправить найденные расхождения.
   Закоммитить ровно четыре внешних документа отдельным коммитом. Его SHA записать как `Validated at` в отчёте:
   RELEASE 1 должен иметь возможность перенести только этот коммит на прежний кандидат, без скрытого переноса CI.
   Затем отдельным коммитом заполнить Executor Report, перевести FIX 1 и строку дашборда в REVIEW. RELEASE 1
   остаётся BLOCKED до приёмки FIX 1; Reviewer при закрытии обновляет зависимость и следующий шаг в `todo.md`.

#### Scope

Изменения пакета: `README.md`, `MIGRATION.md`, `example/README.md`, `CHANGELOG.md` (только запись 0.5.1).
Учёт работы: эта карточка и её строка/следующий шаг в `todo.md`; `COMPLETION.md` — Reviewer при закрытии.

#### Constraints

- Код, тесты, manifests, версии, assets, CI и release branch в этой задаче не меняются.
- Не переписывать исторические CHANGELOG и отчёты RELEASE 1; прежние проверки не объявлять проверками нового SHA.
- Формулировки Web ограничить фактами `doc/web-parity.md`. Не добавлять новые рекомендации о скорости.
- Runtime-пробы и CI для этих Markdown-правок не нужны (`Probe: none`, `scope: none`). Пакетные проверки нового
  кандидата, устройства и CI принадлежат RELEASE 1; публикация, теги выпуска и `main` — Engineer.

#### Definition of Done

1. Четыре документа согласованы по сборкам, операциям и браузерам — check: таблица «документ → раздел → итог»
   против `doc/web-parity.md` — by: Executor.
2. Миграция 0.5.0 → 0.5.1 описана без новых замен API; прежние правила 0.2.4/0.4.0 сохранены — check: чтение diff
   MIGRATION и README против базы, пустой diff публичного контракта — by: Executor.
3. Изменения только в Scope, версия осталась 0.5.1, старые записи CHANGELOG не менялись — check: `git diff`
   по базе и список путей; команды Validation exit 0 и `scope: none` — by: Executor.
4. Отдельный коммит четырёх документов доступен для переноса, отчёт содержит `Validated at`, базу и результаты
   всех пунктов; карточка и дашборд согласованы — check: `git show --stat <Validated at>`, чтение отчёта — by: Executor.
5. Критерии 1–4 выполнены, новых обещаний поддержки нет — check: diff и Executor Report — by: Reviewer.

#### Validation

На Windows из корня пакета; вместо `<base>` подставить базу, записанную при старте:

```sh
git diff --check <base>
bash tool/ci/scope_guard.sh <base>
git diff --name-only <base>
git diff <base> -- README.md MIGRATION.md example/README.md CHANGELOG.md
git diff --exit-code <base> -- lib src assets shaders darwin android pubspec.yaml example/pubspec.lock
```

Критерии: первая и последняя команды exit 0; scope guard exit 0 и `scope: none`; список путей — только Scope.
По diff вручную подтвердить DoD 1–3. Отсутствие новых замен API проверить также против
`git diff 0.5.0 -- lib/yuv_ffi.dart lib/src/yuv/shared test/public_surface_test.dart` (пустой вывод).
После коммита документов `git show --stat <Validated at>` должен содержать ровно четыре внешних Markdown-файла.
Reviewer читает этот diff и отчёт, runtime-проверки не повторяет.

#### Executor Report

Validated at: `de5a5df` (документный коммит; база: `0ae4149448f41dfcb28c73ef35f76397eb5c6ae8`)

| DoD | Проверка | Результат |
| --- | --- | --- |
| 1. Документы согласованы с проверенным Web-статусом | Прочитаны четыре документа и сопоставлены с `doc/web-parity.md` | Chrome JavaScript и `--wasm`; операции совпадают только в проверенных случаях; `chromaSwap` — NV12 only; Safari/Firefox not verified. Новых обещаний нет. |
| 2. Переход 0.5.0 → 0.5.1 не требует API-миграции | Diff `MIGRATION.md` и `README.md` против базы; `git diff --exit-code 0.5.0 -- lib/yuv_ffi.dart lib/src/yuv/shared test/public_surface_test.dart` | Пустой diff публичного контракта; обновление API replacements и повторную миграцию сериализованных кадров не требует. Старые правила 0.2.4/0.4.0 сохранены по смыслу. |
| 3. Только Scope, версия 0.5.1, история CHANGELOG сохранена | `git diff --name-only <base>` и просмотр diff; `git diff --exit-code <base> -- lib src assets shaders darwin android pubspec.yaml example/pubspec.lock`; проверены версии в `pubspec.yaml`, CHANGELOG, podspec и CMake | Пакетный коммит содержит только четыре разрешённых Markdown-файла; запрещённый diff пустой; версии везде 0.5.1, старые записи CHANGELOG не менялись. `bash tool/ci/scope_guard.sh <base>` — exit 0, `scope: none`. |
| 4. Коммит и отчёт готовы к переносу/ревью | `git show --stat de5a5df`; `git diff --check <base>` | exit 0; документный коммит содержит ровно README.md, MIGRATION.md, example/README.md и CHANGELOG.md. База и результаты проверок записаны здесь. |

#### Таблица согласования документов

| Документ | Раздел | Итог против `doc/web-parity.md` |
| --- | --- | --- |
| `MIGRATION.md` | Updating from 0.5.0; Native and Web consumers | Исправление `--wasm` в 0.5.1, Chrome JavaScript/`--wasm` checked cases, Safari/Firefox not verified. |
| `README.md` | Requirements, Platform status, Web backend, Migrating to 0.5.x | Сборки и ограничения уже согласованы; уточнено 0.5.1 и отсутствие API replacements при обновлении с 0.5.0. |
| `example/README.md` | Web запуск | Проверенные операции в Chrome на JavaScript/`--wasm`, `chromaSwap` только NV12, Safari/Firefox not verified; паритет операций не обещает поддержку камеры. |
| `CHANGELOG.md` | Documentation в `## 0.5.1` | Добавлены обе Web-сборки, браузерные границы и отсутствие API replacements для перехода 0.5.0 → 0.5.1; история не менялась. |

#### Validation

На Windows из корня пакета; все команды завершились с exit 0:

- `git diff --check 0ae4149448f41dfcb28c73ef35f76397eb5c6ae8` — exit 0.
- `bash tool/ci/scope_guard.sh 0ae4149448f41dfcb28c73ef35f76397eb5c6ae8` — exit 0, `scope: none`.
- `git diff --name-only <base>` — пакетные изменения только в Scope; дополнительно присутствуют ожидаемые `tasks/0.5.1/FIX-1.md` и `todo.md`.
- `git diff --exit-code <base> -- lib src assets shaders darwin android pubspec.yaml example/pubspec.lock` — exit 0, diff пуст.
- `git diff --exit-code 0.5.0 -- lib/yuv_ffi.dart lib/src/yuv/shared test/public_surface_test.dart` — exit 0, diff пуст.
- `git show --stat --oneline de5a5df` — exit 0, ровно четыре внешних Markdown-файла.

Deviations: none.

Engineer attention: none. Следующий шаг — Reviewer принимает FIX 1; RELEASE 1 остаётся BLOCKED до этой приёмки, после неё Executor формирует новый кандидат и запускает релизный гейт.

#### Review

Заполняет Reviewer: вердикт, принятый SHA, замечания с критериями закрытия, рекомендации Engineer.
