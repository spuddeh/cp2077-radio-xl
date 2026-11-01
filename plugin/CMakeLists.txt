cmake_minimum_required(VERSION 3.21)
project(RadioXL LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(RadioXL SHARED src/Main.cpp)

# RED4ext.SDK is header-only. Its type layouts and the runtime a plugin declares are fixed when the plugin
# is compiled, so each game build gets its own DLL from its own SDK: the current mirror for the newest
# build, and an exported copy at the last commit before a layout change for the one before it
# (plugin/build.ps1). Nothing is ever built inside _source.
set(RADIOXL_SDK_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}/../../../_source/RED4ext.SDK/include" CACHE PATH
    "The RED4ext.SDK include directory this DLL is compiled against")
set(RADIOXL_OUTPUT_NAME "RadioXL" CACHE STRING "The DLL's file name, without .dll")
target_include_directories(RadioXL PRIVATE "${RADIOXL_SDK_INCLUDE}")

target_compile_definitions(RadioXL PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)

set_target_properties(RadioXL PROPERTIES
    OUTPUT_NAME "${RADIOXL_OUTPUT_NAME}"
    SUFFIX ".dll")

# The manifest reader has no game dependency, so it is tested as a plain executable:
#   ctest --test-dir plugin\build -C Release --output-on-failure
enable_testing()
add_executable(RadioXLManifestTests tests/ManifestTests.cpp)

# Sources are UTF-8: the manifest tests carry the titles a station author writes.
if(MSVC)
    target_compile_options(RadioXL PRIVATE /utf-8)
    target_compile_options(RadioXLManifestTests PRIVATE /utf-8)
endif()
add_test(NAME manifest COMMAND RadioXLManifestTests)
