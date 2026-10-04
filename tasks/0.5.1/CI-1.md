# CI 1 — Web CI: обязательный прогон `--wasm`
**Status:** TODO · **Tier:** T3, Reviewer T2 · **Owner:** — · **Depends On:** WEB 4 · **Probe:** none

**Base SHA:** — (база пула `WASM` — в FIX 1)

#### Goal

Сборка `--wasm` сломалась незаметно: `tool/ci/web.ps1` гоняет только JavaScript-сборку. После WEB 4 Web CI должен
ловить регрессию `--wasm` так же, как JavaScript.

#### Architect Decision

1. В `tool/ci/web.ps1` после JavaScript-целей — шаг `--wasm` через существующий `Invoke-WebDrive` с аргументом
   `--wasm`: `probe_web_test.dart`, `shader_probe_web_test.dart`, `all_web_test.dart`. Ожидаемые числа тестов — те же,
   что в таблице `web.ps1` для этих целей. Шаг обязательный: провал любой цели — провал скрипта. Отдельного
   переключателя нет.
2. `reference_web_conversions_test.dart` и камера под `--wasm` в CI не гоняются (покрыты пробой и WEB 4); время
   шага — в отчёт.
3. Workflow `ci-web.yml` не меняется: он вызывает `web.ps1`.
4. Если WEB 4 закрылся без рабочего `--wasm` (`ENGINEER_REQUIRED`), карточка переходит в `BLOCKED` до решения Engineer.

#### Scope

`tool/ci/web.ps1`.

#### Constraints

- JavaScript-часть `web.ps1` и её критерии не меняются.
- ChromeDriver запускается и останавливается как сейчас (порт 4444, сверка major-версий).

#### Definition of Done

- `pwsh -File tool/ci/web.ps1` — PASS, в выводе три цели `--wasm` с `All tests passed`.
- Негативный контроль: шаг `--wasm` на базовом SHA пула (до WEB 4, временный checkout вне основной копии) падает.

#### Validation

- Executor: `pwsh -File tool/ci/web.ps1` на SHA пула; негативный контроль; `bash tool/ci/scope_guard.sh <base>` —
  ключ `smoke`, если его печатает.
- Reviewer: прочитать изменение `web.ps1`; после принятия — тег `ci/web/WASM` на принятый SHA, Web CI зелёный.

#### Executor Report

#### Review
