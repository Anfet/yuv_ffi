# TEST 3 — Срезы проб по операции и формату
**Status:** BLOCKED · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** TEST 2 · **Rejection Count:** 0
**Было:** RA-61 (цикл 0.4.2).

#### Architect Decision
`--dart-define=PROBE_OPS=gray,crop` и `PROBE_FORMATS=i420,nv12` (и одноимённые переменные окружения для VM) сужают матрицу; без них — полная. Работает одинаково в `probe_correctness_test`, `probe_native_test`, `probe_web_test`. Отчёт печатает, какой срез выполнен (`PROBE scope: ops=gray formats=all cases=108/1188`), чтобы частичный прогон нельзя было принять за полный. Эталон и оракул не меняются.

#### Definition of Done
- [ ] Прогон с `PROBE_OPS=gray` выполняет только gray-случаи и сообщает срез
- [ ] Полный прогон без фильтров — прежние 1188 + группа pack/layout
