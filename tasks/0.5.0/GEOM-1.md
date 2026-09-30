# GEOM 1 — Геометрия кадра `FrameGeometry`
**Status:** BLOCKED · **Tier:** T1 · **Owner:** — · **Depends On:** CLEAN 2

#### Goal
`FrameGeometry` в `lib/`: размер кадра, ориентация (поворот + зеркало), `contain`/`cover` (без `fill` — пропорции сохраняются всегда), `alignment`, `zoom`/`focus`, `crop`; `copyWith`. Даёт матрицу для шейдера, трансформацию Canvas, `mapRect`/`mapPoint` и обратное преобразование; правило для ML Kit (поворот — ему, зеркало — после). `visibleRect` и `apply(YuvImage)`: обрезка сырого кадра по видимой области, затем поворот и зеркало существующими операциями, без native; метод у `FrameGeometry`, не новый метод интерфейса `YuvImage`. Тесты: 8 ориентаций × `contain`/`cover` × размеры экрана; метка в кадре совпадает с `mapRect`; `apply()` совпадает попиксельно с отрисованным 1:1. Исправляет в `face_rect_paint.dart` общую формулу для 90°/270° и жёсткий `cover`.

#### Architect Decision
Черновик из плана 0.5.0 (раздел Goal). Architect уточняет решение, Scope, Constraints, Definition of Done и
Validation при старте этапа; до этого карточка не исполняется.

#### Scope
#### Constraints
#### Definition of Done
#### Validation
#### Executor Report
#### Review
