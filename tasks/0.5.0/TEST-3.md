# TEST 3 — Срезы проб по операции и формату
**Status:** TODO · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** TEST 2 · **Rejection Count:** 0
**Было:** RA-61 (цикл 0.4.2).

#### Goal
Запускать матрицу корректности для выбранных операций и исходных форматов, сохраняя полный прогон по умолчанию.
В выводе каждого запуска должно быть видно, какую часть матрицы он проверил.

#### Architect Decision
- Селекторы `PROBE_OPS=gray,crop` и `PROBE_FORMATS=i420,nv12` выбирают пересечение по точным токенам
  `ProbeCase.operation` и `ProbeCase.format` из ID случая. Операции — токены из `test/probe/cases.dart`, форматы —
  `i420`, `nv12`, `bgra8888`; псевдонимы семейств операций не вводятся. Порядок и дубли в списке не меняют результат.
- Для `flutter test` на VM читаются одноимённые переменные окружения; `--dart-define` также принимается и имеет
  приоритет, если заданы оба источника. Для `flutter drive` на native/Web селекторы передаются через
  `--dart-define`. Если селектор не задан, выбирается вся матрица. Пустой или неизвестный токен и выбор без
  случаев завершаются понятной ошибкой, а не зелёным прогоном.
- Перед выбором среза сверяется полный перечень ID с неизменённым golden. Хеши входов и выходов проверяются
  только для выбранных случаев; тестовый negative control берёт первый случай выбранного среза. `PROBE_RECORD`
  без селекторов продолжает работать как раньше; сочетание записи с селекторами отвергается, чтобы частичный
  прогон не переписал полный эталон.
- Одинаковое правило выбора и строка `PROBE scope: ops=<...> formats=<...> cases=<N>/<total>` действуют в
  `test/probe/probe_correctness_test.dart`, `example/integration_test/probe_native_test.dart` и
  `example/integration_test/probe_web_test.dart`. `all` означает отсутствие фильтра. `total` берётся из
  `probeCaseIds`, а не фиксируется в форматировании; сейчас это 1188. `PROBE_OPS=gray` сейчас выбирает 54 случая.
- `test/probe/layout_pack_test.dart` остаётся отдельной группой: селекторы матрицы не должны скрывать её при
  полном прогоне `flutter test` после TEST 2.

#### Scope
- Исполнение после завершения TEST 2: ветка `task/TEST-3` от актуального `dev`, worktree `.worktrees/TEST-3`.
- Селектор и узкие тесты его разбора — в `test/probe/**`; передача выбранных ID — в двух указанных
  `example/integration_test/probe_*_test.dart` и при необходимости в их `helpers/probe/**`; эта карточка.

#### Constraints
- Не менять `test/probe/golden.json`, `example/assets/probe/golden.json`, `example/integration_test/helpers/probe/golden.json`,
  генератор входов, формулы оракула или сами операции. `lib/`, `src/`, публичный API и ABI вне scope.
- Теги TEST 2 сохраняются. Web остаётся частичным WASM backend; проверять фактически доступную матрицу.
- Изменение не затрагивает измерение скорости в `probe_performance_test.dart` и `tool/probe/**`.

#### Definition of Done
- [ ] Без селекторов все три цели сравнивают полные 1188 случаев с тем же golden; отдельный pack/layout тест
      остаётся в полном `flutter test`.
- [ ] `PROBE_OPS=gray` выполняет 54 случая, `PROBE_FORMATS=i420` и совместный срез выбирают только соответствующие
      ID; в каждой цели напечатаны фактические операция, формат и `N/1188`.
- [ ] Ошибочный, пустой и не дающий случаев селектор завершаются ошибкой с причиной; частичный прогон не может
      заявить `all` или изменить golden, включая режим `PROBE_RECORD`.
- [ ] Узкие тесты селектора и соответствующие локальные платформенные проверки из Validation проходят.

#### Validation
- Windows VM: собрать/добавить native DLL тем же способом, что `tool/ci/vm.ps1`; выполнить полный
  `pwsh -File tool/ci/vm.ps1`, затем `flutter test test/probe/probe_correctness_test.dart` без фильтра,
  с `$env:PROBE_OPS='gray'`, с `$env:PROBE_FORMATS='i420'` и с обоими селекторами. После каждого варианта
  удалить эти переменные окружения; проверить строку scope и фактически выбранные ID. Отдельно проверить
  неизвестный/пустой селектор и `PROBE_RECORD` вместе с фильтром как ожидаемые ошибки без изменения golden.
- Native: `pwsh -File tool/ci/windows.ps1` и выборочный вызов
  `tool/ci/drive.ps1 integration_test/probe_native_test.dart windows --dart-define=PROBE_OPS=gray`
  с успешным `All tests passed` и строкой scope. На Android — `pwsh -File tool/ci/android.ps1`.
- Web: `pwsh -File tool/ci/web.ps1` для полного прогона, затем тот же `probe_web_test.dart` с
  `--dart-define=PROBE_OPS=gray` через `tool/ci/drive.ps1` при запущенном ChromeDriver, как в `web.ps1`.
  Зафиксировать строку scope и проверку `All tests passed`.
- Mac через mac-runner: `bash tool/ci/macos.sh` и `bash tool/ci/ios.sh` для затронутой integration-цели.
  В Executor Report указать команды, SHA, выбранное число случаев и результат каждого требуемого прогона.

#### Executor Report

#### Review
