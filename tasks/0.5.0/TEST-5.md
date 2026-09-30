# TEST 5 — Чистка дублирующих тестов
**Status:** ARCHITECT_REQUIRED · **Tier:** T2 · **Owner:** — · **Depends On:** TEST 1, TEST 2

#### Goal
Каждое удаление доказывается мутацией: ошибка, от которой защищает тест, ловится другим тестом. Кандидаты: `conversions_test` / `reference_native_conversions_test` / `independent_results_test` / пробы; `test/web/wasm_parity_*` против `example/integration_test/*_web_test`. Независимый эталон вместо собственного кода — libyuv ([`doc/independent-oracles.md`](doc/independent-oracles.md)).

#### Architect Decision
Черновик из плана 0.5.0 (раздел Goal). Architect уточняет решение, Scope, Constraints, Definition of Done и
Validation при старте этапа; до этого карточка не исполняется.

#### Scope
#### Constraints
#### Definition of Done
#### Validation
#### Executor Report
#### Review
