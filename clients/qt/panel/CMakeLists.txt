# The reference Qt panel: a managed interface built against the published C++ family, found by
# find_package as any consumer finds it, and Qt's widgets.
cmake_minimum_required(VERSION 3.25)
project(panel LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC OFF)

# 0.6 left out the administrative contract, which the panel never used; both are what it builds against.
# The family's version file accepts one minor version alone, so the two are checked here.
find_package(yoke-sdk-cpp REQUIRED)
if(yoke-sdk-cpp_VERSION VERSION_LESS 0.5 OR NOT yoke-sdk-cpp_VERSION VERSION_LESS 0.7)
    message(FATAL_ERROR "the panel builds against yoke-sdk-cpp 0.5 or 0.6, and found ${yoke-sdk-cpp_VERSION}")
endif()
find_package(Qt6 REQUIRED COMPONENTS Widgets)

add_library(panel-lib STATIC src/picture.cpp src/window.cpp)
target_include_directories(panel-lib PUBLIC src)
target_link_libraries(panel-lib PUBLIC yoke::yoke-cpp Qt6::Widgets)
target_compile_options(panel-lib PRIVATE -Wall -Wextra -Werror)

add_executable(panel src/main.cpp)
target_link_libraries(panel PRIVATE panel-lib)
target_compile_options(panel PRIVATE -Wall -Wextra -Werror)

add_executable(panel_test tests/panel_test.cpp)
target_compile_definitions(panel_test PRIVATE SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(panel_test PRIVATE panel-lib)
target_compile_options(panel_test PRIVATE -Wall -Wextra -Werror)
