# The reference LVGL panel: a managed interface built against the published C family, found by find_package
# as any consumer finds it, and LVGL: the one the build provides, as an image build provides one, or else its
# release, taken by the digest this file pins.
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

# An LVGL the build provides is found by pkg-config, which is how an installed LVGL says where it is; its
# headers are under the directory it names or in lvgl/ there, as LVGL's releases have put them. It draws to a
# framebuffer on a device, so it must carry the Linux framebuffer driver.
find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
    pkg_check_modules(LVGL QUIET IMPORTED_TARGET lvgl>=9.4)
endif()
add_library(panel-lvgl INTERFACE)
if(LVGL_FOUND)
    find_path(PANEL_LVGL_HEADERS lvgl.h HINTS ${LVGL_INCLUDE_DIRS} PATH_SUFFIXES lvgl NO_DEFAULT_PATH)
    if(NOT PANEL_LVGL_HEADERS)
        message(FATAL_ERROR "the LVGL the build provides, ${LVGL_VERSION}, has no lvgl.h under ${LVGL_INCLUDE_DIRS}")
    endif()
    include(CheckCSourceCompiles)
    set(CMAKE_REQUIRED_INCLUDES ${PANEL_LVGL_HEADERS} ${LVGL_INCLUDE_DIRS})
    set(CMAKE_REQUIRED_DEFINITIONS ${LVGL_CFLAGS_OTHER})
    check_c_source_compiles("#include <lvgl.h>
#if !LV_USE_LINUX_FBDEV
#error no framebuffer driver
#endif
int main(void) { return 0; }" PANEL_LVGL_DRAWS_TO_A_FRAMEBUFFER)
    unset(CMAKE_REQUIRED_INCLUDES)
    unset(CMAKE_REQUIRED_DEFINITIONS)
    if(NOT PANEL_LVGL_DRAWS_TO_A_FRAMEBUFFER)
        message(FATAL_ERROR "the LVGL the build provides, ${LVGL_VERSION}, carries no Linux framebuffer driver (LV_USE_LINUX_FBDEV)")
    endif()
    message(STATUS "LVGL ${LVGL_VERSION}: the one the build provides, in ${PANEL_LVGL_HEADERS}")
    target_include_directories(panel-lvgl INTERFACE ${PANEL_LVGL_HEADERS})
    target_link_libraries(panel-lvgl INTERFACE PkgConfig::LVGL)
else()
    # Outside such a build, LVGL's release, downloaded by its digest; a build that may not download and is given
    # no LVGL is refused here rather than later.
    set(PANEL_LVGL_URL https://github.com/lvgl/lvgl/archive/refs/tags/v9.6.0.tar.gz)
    set(PANEL_LVGL_HASH SHA256=b20ee3acc1bba13c62d854f9ebd62e4c51e0b443b1e0225892e86442defa84df)
    if(FETCHCONTENT_FULLY_DISCONNECTED)
        message(FATAL_ERROR "LVGL: the build provides none, by pkg-config, and may not download its release")
    endif()
    set(PANEL_LVGL_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/lvgl-9.6.0.tar.gz")
    file(DOWNLOAD ${PANEL_LVGL_URL} "${PANEL_LVGL_ARCHIVE}" EXPECTED_HASH ${PANEL_LVGL_HASH} STATUS downloaded)
    list(GET downloaded 0 code)
    if(NOT code EQUAL 0)
        list(GET downloaded 1 why)
        message(FATAL_ERROR "LVGL: the build provides none, by pkg-config, and its release cannot be downloaded: ${why}")
    endif()
    include(FetchContent)
    set(LV_CONF_PATH "${CMAKE_CURRENT_SOURCE_DIR}/lv_conf.h" CACHE STRING "" FORCE)
    set(CONFIG_LV_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(CONFIG_LV_BUILD_DEMOS OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(lvgl URL "${PANEL_LVGL_ARCHIVE}" URL_HASH ${PANEL_LVGL_HASH})
    FetchContent_MakeAvailable(lvgl)
    message(STATUS "LVGL 9.6.0: its release, by the digest this file pins")
    target_link_libraries(panel-lvgl INTERFACE lvgl::lvgl)
endif()

add_library(panel-lib STATIC src/picture.c src/ui.c src/display.c)
target_include_directories(panel-lib PUBLIC src)
target_link_libraries(panel-lib PUBLIC yoke::yoke-c panel-lvgl Threads::Threads)
target_compile_options(panel-lib PRIVATE -Wall -Wextra -Werror)
target_compile_definitions(panel-lib PRIVATE _GNU_SOURCE)

add_executable(panel src/main.c)
target_link_libraries(panel PRIVATE panel-lib)
target_compile_options(panel PRIVATE -Wall -Wextra -Werror)

add_executable(panel_test tests/panel_test.c)
target_compile_definitions(panel_test PRIVATE SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(panel_test PRIVATE panel-lib)
target_compile_options(panel_test PRIVATE -Wall -Wextra -Werror)
