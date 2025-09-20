# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(yuv_ffi_library VERSION 0.0.1 LANGUAGES C)

set_property(GLOBAL PROPERTY CMAKE_CONFIGURE_DEPENDS "yuv/*.c")

# Собираем все исходники из папки yuv/
file(GLOB_RECURSE SOURCES "yuv/*.c" "yuv_ffi.c" "**/*.c")
add_library(
    yuv_ffi SHARED ${SOURCES} "yuv_ffi.c"
)

target_include_directories(
        yuv_ffi
        PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}
        PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}
        PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/yuv
)

set_target_properties(yuv_ffi PROPERTIES
        PUBLIC_HEADER yuv_ffi.h
        OUTPUT_NAME "yuv_ffi"
)

target_compile_definitions(yuv_ffi PUBLIC DART_SHARED_LIB)

# Связка с liblog (Android logcat)
target_link_libraries(
        yuv_ffi
        log
)

if (ANDROID)
    # Support Android 15 16k page size
    target_link_options(yuv_ffi PRIVATE "-Wl,-z,max-page-size=16384")
endif()


