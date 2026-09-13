# yuv_ffi: аудит Dart-классов и архитектуры

Первичный аудит Dart-слоя выполнен 2026-09-13 на ветке
`fix/0.2.5-release-readiness`, commit `1fd3a7b`. Документ синхронизирован с
`todo.md` и повторно сверен на commit `bfa85d7` после реализации YUV-07,
YUV-17, YUV-20 и YUV-21.

Область: Dart-классы и архитектура package. Native C и WASM build internals не
входят в этот аудит. Найденные native/build вопросы зарегистрированы в
`todo.md` отдельно и подчиняются approval policy из `AGENTS.md`.

Этот файл хранит выводы и их обоснование. Исполняемый backlog, модели, DoD и
результаты находятся только в `todo.md`; воспроизведённые runtime/reference
падения — в `failed-test-cases.md`.

## Актуальное соответствие `todo.md`

| Находка | Задача | Актуальный статус | Решение при синхронизации |
|---|---|---|---|
| A-01: alias planes после `crop`/`rotate` | — | RETRACTED | Наблюдаемый alias наружу не доказан; отдельная задача не создана |
| A-02: backend duplication | YUV-28 | BLOCKED / post-release | Пересчитать duplication после `0.2.5`, затем выделять только подтверждённый shared layer |
| A-03: разные empty accessors | YUV-28 | NOTE / post-release | Contract debt включён в characterization scope YUV-28 |
| A-04: тела методов в `interface class` | — | RETRACTED | `implements` уже требует реализацию всех instance members на compile time |
| A-05: `DataReader`/`ChangeNotifier` | YUV-07 | REJECTED | Удалить мёртвый reader/writer после миграции на codec |
| A-05: `bytesPerPixes`, exception, rotation naming | YUV-27 | DONE / archived | Source-compatible cleanup принят и перемещён в `completed-tasks.md` |
| A-06: rotation assert и `dstWidtn` | YUV-27 | DONE / archived | Механическая cleanup принята без изменения semantics |
| A-07: `getBytes()` backing buffer | YUV-14 | READY FOR REVIEW | Реализовано commit `3bd12bf`; нужен обязательный Web retest |
| A-08: bindings cache | YUV-19 | DONE / archived | Принято и перемещено в `completed-tasks.md` |
| A-08: serialization | YUV-07 | REJECTED | Streaming реализован, но format-specific geometry проверяется после чтения plane |
| A-08: image cache | YUV-20 | REJECTED | Interface break исправлен, но foreign implementations получили stale-cache regression |
| A-08: initialization | YUV-21 | READY FOR REVIEW | Реализовано commit `ad92431`; требуется Web runtime evidence |
| A-09: локальный `_tmp_*` | — | CLOSED / local | Файл отсутствует; удаление локальных tmp не является package task |
| A-10: revision compatibility | YUV-20 | REJECTED | Compile compatibility восстановлена; для legacy mutators нужно сохранить safe cache miss |
| A-11: поздняя geometry validation | YUV-07 | REJECTED | Самосогласованная, но неверная metadata должна отклоняться до чтения plane body |

Дополнительная синхронизация build/tooling backlog:

- бывшая YUV-25 объединена с YUV-06: macOS forwarders являются частью одного
  packaging/runtime outcome;
- YUV-26 оставлена только для ffigen filters и больше не требует native-header
  permission;
- удаление `nv21_to_rgb` из headers вынесено в YUV-29 и остаётся `BLOCKED` до
  явного разрешения;
- optional YUV-24/YUV-26/YUV-29 и post-release YUV-28 исключены из
  release dependencies YUV-18.

## Основание проверки

Первичный snapshot:

```text
flutter analyze --no-pub                         -> 9 issues из локального _tmp-файла
flutter analyze --no-pub (без локального _tmp)   -> No issues found
flutter test test/yuv_plane_validation_test.dart
             test/native_allocation_safety_test.dart -> All tests passed (31)
```

После snapshot ветка получила commits:

```text
3bd12bf  fix: removed the getBytes alignment tail
e3c235d  fix: keyed the image cache by frame revision
ad92431  fix: pinned the IO and Web initialization contract
c52e13c  fix: hardened the save/load format
bfa85d7  ci: analyzed and built the example as its own package
```

Статусы выше основаны на diff/code review этих commits и записанном evidence в
`todo.md`. Они не подменяют обязательный clean CI/Web run. В частности,
результаты YUV-07/YUV-20/YUV-21 были записаны для Flutter 3.38.10, тогда как
целевая версия ветки — Flutter 3.44.9.

---

## A-01 — предполагавшийся alias planes в IO `crop()`/`rotate()`

- Статус: RETRACTED
- Исходный приоритет: P1
- Отдельная задача: не нужна

### Первоначальное наблюдение

IO присваивает `_planes = dst.planes`, тогда как соседние conversions и Web
часто делают `.map((p) => p.copy())`. Был сделан вывод, что `this` и временный
`dst` сохраняют совместное владение mutable planes.

### Повторная оценка

`dst` является локальным объектом и не возвращается вызывающему коду. После
присваивания внешнего наблюдаемого второго владельца нет. `List.unmodifiable`
создаёт отдельный unmodifiable list, содержащий те же elements; структура
`_planes` нигде не мутируется in-place, а заменяется целиком. Поэтому ни
публичный alias, ни достижимый `UnsupportedError` исходным аудитом не доказаны.

Различие копирования между IO/Web можно устранить как performance/ownership
cleanup после измерения, но регистрировать его P1 correctness defect нельзя.

---

## A-02 — дублирование между IO/Web/stub backend

- Статус: OPEN
- Приоритет: P2 / architecture
- Задача: YUV-28, только после `0.2.5`

Три `YuvImageImpl` повторяют state, constructors, plane accessors, copy/bytes
logic и значительную часть format dispatch. Риск расхождения реален, но
первичная оценка «около 700 строк» устарела: `YuvGeometry` и `YuvCodec` уже
вынесли часть общей политики.

Полный `YuvImageBase` не следует создавать автоматически. Сначала нужен новый
duplication map после закрытия YUV-07/YUV-20. Предпочтительный порядок:

1. shared codec/geometry/state через composition;
2. platform dispatch остаётся в `impl/*_io.dart` и `impl/*_web.dart`;
3. characterization tests фиксируют поведение до перемещения;
4. Web продолжает считаться partial WASM backend.

Эта работа не входит в release scope `0.2.5` и не блокирует YUV-18.

---

## A-03 — разные accessors на пустом состоянии

- Статус: NOTE
- Приоритет: P3
- Задача: включено в YUV-28

IO обращается к `_planes[0]` и бросает `RangeError`; Web/stub возвращают
zero-length `_emptyPlane`. Контракт действительно не описан одинаково.

Первичный аудит, однако, переоценил риск shared mutable sentinel. Его buffer
имеет длину 0: `setPixel()` бросает, а `assignFrom(Uint8List(0))` не способен
изменить содержательное состояние. Кроме того, после общей positive-geometry
validation пустое состояние не должно возникать у нормально созданного public
image.

До изменения реализации YUV-28 должна сначала доказать достижимость состояния
и зафиксировать выбранный contract тестом.

---

## A-04 — методы с телами в `abstract interface class YuvImage`

- Статус: RETRACTED
- Отдельная задача: не нужна

Верно, что concrete bodies не наследуются классом, использующим `implements`.
Неверен исходный вывод, будто они скрывают пропущенные реализации до runtime:
Dart требует от `implements YuvImage` реализовать все instance members,
независимо от наличия тела, и сообщает о пропуске на compile time.

Удаление `=> throw UnimplementedError()` может остаться style cleanup, но не
исправляет заявленный correctness defect и не должно расширять текущий релиз.

---

## A-05 — подтверждённый Dart API debt

- Статус: PARTIALLY OPEN
- Задачи: YUV-07 и YUV-27

### Подтверждено

- `DataReader with ChangeNotifier` и `DataWriter` после commit `c52e13c` не
  имеют consumers. Удаление находится в исходном scope YUV-07 и не требует
  отдельной карточки.
- `bytesPerPixes` — typo в публичном getter. Исправление должно добавить
  `bytesPerPixel`, сохранив старое имя как deprecated forwarding alias.
- `NotSupportedException` не экспортируется и не используется. Его можно
  удалить после контрольного поиска; произвольно заменять им существующие типы
  ошибок нельзя.
- IO rotation содержит недостижимый enum assert и локальную опечатку
  `dstWidtn`; это безопасный Dart cleanup без изменения поведения.

### Требует characterization, а не немедленного fix

`YuvImageRotation.toZero()` возвращает текущее enum value. Название неоднозначно,
но example может осознанно использовать значение как transform, приводящий
frame к zero orientation. Семантическое изменение без orientation regression
создало бы риск нового визуального дефекта. Решение и DoD записаны в YUV-27.

---

## A-06 — rotation validation drift

- Статус: LOW-RISK CLEANUP
- Задача: YUV-27

Невалидный угол недостижим через текущий enum API. Release-mode safety defect
не подтверждён. YUV-27 удаляет redundant assert и исправляет имя локальной
переменной, сохраняя результаты 0/90/180/270 без изменений.

---

## A-07 — `getBytes()` возвращал backing buffer

- Статус: READY FOR REVIEW
- Задача: YUV-14 / F-003
- Commit: `3bd12bf`

Первичный аудит подтвердил лишний хвост на малых и обычных размерах и внешний
consumer в example/ML Kit. Реализация исправлена для IO/Web, добавлены tests на
точное равенство длины сумме planes. `DONE` пока запрещён зависимостью от
реального Web runtime YUV-02.

Исторические измерения сохранены как evidence:

```text
i420 16x16:   sumPlanes=512    getBytes=1024
i420 100x100: sumPlanes=20000  getBytes=40000
i420 63x47:   sumPlanes=6033   getBytes=11844
```

---

## A-08 — сверка ранее зарегистрированных задач

- YUV-19 bindings cache — DONE, данные в `completed-tasks.md`.
- YUV-07 shared serialization — основа реализована в `c52e13c`, streaming в
  `ded01b0`, но задача повторно возвращена в REJECTED по A-11.
- YUV-20 provider cache — functional seam реализован в `e3c235d`, interface
  compatibility исправлена в `a6851d7`, но задача повторно возвращена в
  REJECTED по A-10.
- YUV-21 initialization contract — READY FOR REVIEW, Web evidence зависит от
  YUV-02.
- YUV-06 loader paths/macOS packaging — BLOCKED до разрешения на C-forwarders;
  бывшая отдельная YUV-25 объединена с этой карточкой.

---

## A-09 — локальный `_tmp_pub_wasm_loader_web.dart`

- Статус: CLOSED / local artifact
- Отдельная задача: не нужна

Файл, дававший девять diagnostics, больше отсутствует в рабочем дереве.
Он был untracked и покрывался ignore policy, поэтому package/CI defect не
создавал. Общее правило остаётся: не удалять пользовательские `_tmp_*` без
подтверждения и не превращать локальную уборку в release dependency.

---

## A-10 — YUV-20 меняет cache behavior внешних `implements YuvImage`

- Статус: OPEN / implementation REJECTED
- Приоритет: P1
- Задача: расширена YUV-20

Commit `a6851d7` исправил исходный interface break: revision вынесен в
неэкспортируемый `YuvRevisionAware`, а прежний внешний `implements YuvImage`
снова компилируется. Эта часть находки закрыта.

Остался behavioral regression. До YUV-20 provider key использовал identity
самого provider, поэтому каждый rebuild неизвестного внешнего image давал
безопасный cache miss. Теперь foreign image получает revision из `Expando`, но
его legacy mutators не знают о новом `markDirty()`. После in-place mutation
identity и revision остаются прежними, и новый provider способен вернуть stale
frame.

Для `0.2.5` revision-based cache key должен использоваться только для package
backend либо для явно opt-in внешнего revision contract. Неизвестная legacy
реализация должна сохранить прежний safe always-miss. Compile fixture нужно
расширить реально мутирующим стандартным методом без `markDirty()`.

---

## A-11 — YUV-07 поздно проверяет format-specific geometry

- Статус: OPEN / implementation REJECTED
- Приоритет: P2
- Задача: расширена YUV-07

Commit `ded01b0` убрал whole-stream collection, удалил мёртвые
`DataReader`/`DataWriter` и добавил последовательный cursor. Предыдущее описание
этой находки больше не актуально.

Оставшийся дефект уже: перед `readBytes()` проверяются только предел длины и
равенство `planeHeight * rowStride == byteLength`. Соответствие высоты формату,
минимальный row stride и допустимый pixel stride проверяются общим
`YuvGeometry.validateImage()` лишь после чтения всех bytes и создания
`YuvPlane`. Самосогласованная, но заведомо неверная metadata способна заставить
decoder ждать или копировать до 1 GiB перед отказом.

YUV-07 должна вычислить ожидаемую geometry каждой plane из header/format и
отклонить несовместимые metadata до чтения body. Regression обязан использовать
незакрытый stream: после валидной по арифметике, но неверной для формата metadata
decoder должен завершиться `FormatException`, не запросив plane bytes.

---

## Порядок работ после синхронизации

### До release acceptance

1. Исправить замечания YUV-07 и YUV-20; вернуть их в READY FOR REVIEW только с
   Flutter 3.44.9 evidence.
2. Независимо проверить READY FOR REVIEW задачи YUV-14, YUV-15, YUV-17,
   YUV-21; Web-зависимые не переводить в DONE до YUV-02.
3. После явного native permission выполнить единым scope YUV-06, включая
   macOS source forwarding, затем YUV-22/YUV-23.
4. Закрыть reference/Web/documentation dependencies и выполнить YUV-18.

### Опционально, не блокирует `0.2.5`

- YUV-24 — CMake source discovery cleanup после разрешения.
- YUV-26 — host-independent ffigen filtering без изменения native headers.
- YUV-27 завершена и перемещена в `completed-tasks.md`.
- YUV-29 — удалить dead native declaration после отдельного разрешения.

### После `0.2.5`

- YUV-28 — повторно измерить и сократить backend duplication, включая
  documented empty-state contract. Не переносить в него RETRACTED A-01/A-04 как
  якобы подтверждённые bugs.
