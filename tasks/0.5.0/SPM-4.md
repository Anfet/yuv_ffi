# SPM 4 — Документация: SPM и CocoaPods для iOS/macOS
**Status:** BLOCKED · **Tier:** T3 · **Owner:** SPM 2 · **Depends On:** SPM 2 · **Probe:** none

#### Goal
D-12, шаг 4 из 4. Описать для пользователей пакета, что iOS и macOS собираются через Swift Package Manager или
CocoaPods без настройки, и записать изменение в CHANGELOG.

#### Architect Decision
Факты для текста (проверены в SPM 1 и SPM 2, перепроверять не нужно):
- плагин поддерживает оба менеджера: Flutter 3.44 по умолчанию использует SPM, при
  `enable-swift-package-manager: false` — CocoaPods; потребителю ничего настраивать не нужно;
- минимальные версии: iOS 13.0, macOS 10.15 (у macOS было 10.11; Flutter сам требует 10.15, поэтому для
  приложений это не меняет требований);
- Apple-часть плагина теперь лежит в `darwin/` (`sharedDarwinSource`), C-исходники — по-прежнему в `src/`.

Ограничение example (не пакета): `google_mlkit_face_detection` не поддерживает arm64 на iOS 26+ Simulator;
example на симуляторе запускать с iOS 18.x или на устройстве.

#### Scope
Worktree `.worktrees/SPM-4`, ветка `task/SPM-4` от `dev`.

- `README.md` (английский): короткий раздел про iOS/macOS — оба менеджера, минимальные версии, настраивать
  ничего не нужно. Место — рядом с описанием поддерживаемых платформ.
- `CHANGELOG.md`: в верхнюю запись 0.5.0 (её создаёт CLEAN 2 по D-14/D-15) — строки про поддержку SPM,
  сохранённый CocoaPods и macOS 10.15. Если верхней записи 0.5.0 ещё нет — остановиться с `BLOCKED`: запись и
  версию создаёт CLEAN 2.
- `example/README.md` (английский): ограничение ML Kit на iOS 26+ Simulator.

#### Constraints
- Только эти три файла. Внешние тексты на английском (D-7), без истории задач и внутренних ID.
- Версии в `pubspec.yaml` и podspec не трогать.

#### Definition of Done
- [ ] README описывает SPM и CocoaPods и минимальные версии iOS/macOS.
- [ ] Верхняя запись CHANGELOG содержит изменение и совпадает по версии с `pubspec.yaml`.
- [ ] example/README описывает ограничение ML Kit на симуляторе.

#### Validation
- `Probe: none`, ключи путей пустые (`*.md`): прогоны скриптов не нужны.
- Сверить, что версия верхней записи `CHANGELOG.md` совпадает с `version:` в `pubspec.yaml`.
- В Executor Report — изменённые разделы и результат сверки версии.

#### Executor Report
#### Review
