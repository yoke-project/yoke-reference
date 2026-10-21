# The reference LVGL panel: a managed interface built against the published C family, found by find_package
# as any consumer finds it, and LVGL, taken from its release by the digest this file pins.
cmake_minimum_required(VERSION 3.25)
project(panel LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS ON)

# The interface library of the C family arrived with 0.6.
find_package(yoke-sdk-c REQUIRED)
if(yoke-sdk-c_VERSION VERSION_LESS 0.6)
    message(FATAL_ERROR "the panel builds against yoke-sdk-c 0.6 or later, and found ${yoke-sdk-c_VERSION}")
endif()
find_package(Threads REQUIRED)

include(FetchContent)
set(LV_CONF_PATH "${CMAKE_CURRENT_SOURCE_DIR}/lv_conf.h" CACHE STRING "" FORCE)
set(CONFIG_LV_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(CONFIG_LV_BUILD_DEMOS OFF CACHE BOOL "" FORCE)
FetchContent_Declare(lvgl
    URL https://github.com/lvgl/lvgl/archive/refs/tags/v9.6.0.tar.gz
    URL_HASH SHA256=b20ee3acc1bba13c62d854f9ebd62e4c51e0b443b1e0225892e86442defa84df)
FetchContent_MakeAvailable(lvgl)

add_library(panel-lib STATIC src/picture.c src/ui.c src/display.c)
target_include_directories(panel-lib PUBLIC src)
target_link_libraries(panel-lib PUBLIC yoke::yoke-c lvgl::lvgl Threads::Threads)
target_compile_options(panel-lib PRIVATE -Wall -Wextra -Werror)
target_compile_definitions(panel-lib PRIVATE _GNU_SOURCE)

add_executable(panel src/main.c)
target_link_libraries(panel PRIVATE panel-lib)
target_compile_options(panel PRIVATE -Wall -Wextra -Werror)

add_executable(panel_test tests/panel_test.c)
target_compile_definitions(panel_test PRIVATE SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(panel_test PRIVATE panel-lib)
target_compile_options(panel_test PRIVATE -Wall -Wextra -Werror)
