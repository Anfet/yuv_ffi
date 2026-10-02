# DEVICE 1 — Проверка на Pixel 3
**Status:** BLOCKED · **Tier:** T2 · **Owner:** — · **Depends On:** CAMERA 2

#### Goal
Release: прямое превью + тяжёлая обработка раз в секунду (FPS превью не падает); рамки лиц в портрете и альбоме; «снимок = видимое»; повтор стенда VIEW-04 на новых виджетах.

Стенд тяжёлой обработки — отладочный переключатель `CameraScreen` из CAMERA 2. После повтора стенда VIEW-04 удалить
прототип: `example/shaders/view04_i420.frag`, `example/lib/view04_*.dart`, запись шейдера в `example/pubspec.yaml`,
`CameraImageExt.toYuvImage` в `example/lib/ext.dart`, если у него не останется пользователей (SHADER 2, решение 4;
CAMERA 1, решение 3).

#### Architect Decision
Черновик из плана 0.5.0 (раздел Goal). Architect уточняет решение, Scope, Constraints, Definition of Done и
Validation при старте этапа; до этого карточка не исполняется.

#### Scope
#### Constraints
#### Definition of Done
#### Validation
#### Executor Report
#### Review
