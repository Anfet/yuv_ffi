# OPT-14 — Dart row-copy fast paths

Статус: REVIEW. Эксперимент выполнен на Windows x64, Dart 3.12.2 и Flutter
3.44.9, от базы `8e6e8bb`. Production source не менялся. Кандидатный
[patch](opt14_row_copy_candidate.patch) применён только в отдельном worktree.

## Гипотеза

В двух Dart путях sample-wise копирование заменяется на один `setRange` на
активную строку:

- `_seedPlaneFromSource`: только если source и destination имеют
  `pixelStride == sampleBytes`;
- `YuvAbiV1ImageTransport.applyTo`: только если target имеет
  `pixelStride == sampleBytes`, поскольку source result всегда tight.

Копируется `planeWidth * sampleBytes`, а не `rowStride`: padding назначения
остается нетронутым. Для gapped pixel stride ветка не включается.

## Измерение

Вход: BGRA 1920×1080, `sampleBytes=4`, `pixelStride=4`,
`rowStride=7744` (64 байта row padding). Five warmups, 25 samples; fixture и
проверка padding находятся вне таймера. ROI seed вызывает runner с injected
OK status, поэтому измеряет Dart allocation/staging/seed без native kernel.
Copy-back вызывает `applyTo` на таком же padded receiver; его reset до
canary `0xA5` является частью каждого образца и одинаков для baseline и
кандидата.

| Путь | Baseline median | Row-copy median | Ускорение | Экономия |
| --- | ---: | ---: | ---: | ---: |
| ROI seed | 49.403 ms | 27.190 ms | 1.82× | 44.96% |
| `applyTo` copy-back | 45.194 ms | 11.844 ms | 3.82× | 73.79% |

Это время Dart path, а не полного blur вызова. Оно показывает, что padding
receiver больше не вынуждает обходить каждый sample отдельно; эффект на
конкретной публичной операции зависит от native kernel и размера кадра.

## Корректность

В candidate worktree прошли:

```powershell
flutter test test/opt14_copy_contract_test.dart test/abi_status_mapping_test.dart -r expanded
flutter analyze lib/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart lib/src/yuv/shared/yuv_abi_v1_image_transport.dart
```

`opt14_copy_contract_test.dart` проверяет postrочное копирование в padded
receiver, сохранение row padding и fallback на gapped target. Второй тест
проверяет gapped source → tight destination в ROI seed: gaps не попадают в
активные bytes. Все запущенные тесты прошли. Native-dependent тесты в
`abi_status_mapping_test.dart` были skipped, так как на Windows хосте не
было доступной native `yuv_ffi` library; значения fast path от native кода не
зависят, поскольку оба пути выполняются в Dart до/после вызова.

Рекомендация: перенести ровно этот узкий patch с адресными тестами в
production отдельной задачей. `calloc`, ABI, allocator и Web runner менять
не нужно.
