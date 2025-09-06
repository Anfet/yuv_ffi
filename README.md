# yuv_ffi

Набор высокопроизводительных C/FFI-рутину для работы с YUV-буферами (YUV420, NV21 и др.) с биндингами для Dart/Flutter.

- 🚀 Конверсии: **YUV420 ↔ NV21**
- ✂️ Кроп: **crop NV21**, crop YUV420
- 🧩 Работа с плоскостями и stride
- 🔗 Чистые FFI-вызовы без платформенных плагинов
- 🧪 Тесты на корректность размеров/границ

> Библиотека предназначена для оффлайн-обработки кадров камеры, предпревью, постпроцессинга и подготовки текстур.

## Установка

Добавь в `pubspec.yaml`:

```yaml
dependencies:
  yuv_ffi:
    git:
      url: https://github.com/Anfet/yuv_ffi.git
```

## Сборка нативной библиотеки

Библиотека использует общий C-код, собираемый в динамическую библиотеку:

- **Android**: `libyuv_ffi.so` (ABI: arm64-v8a, armeabi-v7a, x86_64)
- **iOS/macOS**: `libyuv_ffi.dylib` или статическая `.a`
- **Windows**: `yuv_ffi.dll`
- **Linux**: `libyuv_ffi.so`

### Быстрый путь (CMake)

```
/native
  CMakeLists.txt
  yuv_ffi.c
  yuv_ffi.h
```

Пример `CMakeLists.txt`:

```cmake
cmake_minimum_required(VERSION 3.10)
project(yuv_ffi C)
set(CMAKE_C_STANDARD 99)

add_library(yuv_ffi SHARED
    yuv_ffi.c
)

target_include_directories(yuv_ffi PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
```

Сборка (Linux/macOS):

```bash
mkdir -p build && cd build
cmake ..
cmake --build . --config Release
```

#### Android (через NDK)

Добавь в `android/app/build.gradle`:

```gradle
android {
  defaultConfig { ndk { abiFilters "arm64-v8a", "armeabi-v7a", "x86_64" } }
  externalNativeBuild { cmake { path "../../native/CMakeLists.txt" } }
  sourceSets { main { jniLibs.srcDirs = ['src/main/jniLibs'] } }
}
```

Скопируй артефакты `.so` в соответствующие `jniLibs/<abi>/`.

#### iOS

Варианты:
- собрать статическую `libyuv_ffi.a` и подключить через `.podspec` как `vendored_libraries`,
- либо собрать `.dylib` и добавить в Xcode (Embed & Sign).

## API (C)

```c
// Базовое описание буфера YUV420
typedef struct {
    const uint8_t *y;
    const uint8_t *u;
    const uint8_t *v;
    int width;
    int height;
    int stride_y;
    int stride_u;
    int stride_v;
} YUV420Def;

// Конвертация YUV420 -> NV21
void yuv420_to_nv21(const YUV420Def *src, uint8_t *dst_y, uint8_t *dst_vu);

// Конвертация NV21 -> YUV420
void nv21_to_yuv420(const uint8_t *src_y, const uint8_t *src_vu, int width, int height,
                    YUV420Def *dst);

// Кроп NV21 (координаты кратны 2)
int nv21_crop(const uint8_t *src_y, const uint8_t *src_vu, int src_w, int src_h,
              int x, int y, int w, int h,
              uint8_t *out_y, uint8_t *out_vu);
```

> ⚠️ Для субдискретизации 4:2:0 все `x`, `y`, `w`, `h` должны быть **чётными**.

## Пример использования из Dart (FFI)

```dart
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _Yuv420ToNv21C = ffi.Void Function(
  ffi.Pointer<YUV420Def>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>
);

class YUV420Def extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> y;
  external ffi.Pointer<ffi.Uint8> u;
  external ffi.Pointer<ffi.Uint8> v;
  @ffi.Int32()
  external int width;
  @ffi.Int32()
  external int height;
  @ffi.Int32()
  external int stride_y;
  @ffi.Int32()
  external int stride_u;
  @ffi.Int32()
  external int stride_v;
}

class YuvFfi {
  late final ffi.DynamicLibrary _lib;
  late final void Function(
    ffi.Pointer<YUV420Def>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>
  ) yuv420ToNv21;

  YuvFfi() {
    _lib = Platform.isAndroid
        ? ffi.DynamicLibrary.open('libyuv_ffi.so')
        : Platform.isWindows
            ? ffi.DynamicLibrary.open('yuv_ffi.dll')
            : ffi.DynamicLibrary.open('libyuv_ffi.dylib');

    yuv420ToNv21 = _lib
        .lookupFunction<_Yuv420ToNv21C, void Function(
          ffi.Pointer<YUV420Def>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>
        )>('yuv420_to_nv21');
  }
}
```

## Лицензия

[MIT](./LICENSE)
