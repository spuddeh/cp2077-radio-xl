cmake_minimum_required(VERSION 3.21)
project(RadioXL LANGUAGES CXX)

include(red4ext-plugin.cmake)

add_library(RadioXL SHARED src/Main.cpp)
red4ext_plugin(RadioXL)

# The manifest reader has no game dependency, so it is tested as a plain executable:
#   ctest --test-dir plugin\build\2.5 -C Release --output-on-failure
enable_testing()
add_executable(RadioXLManifestTests tests/ManifestTests.cpp)
target_compile_features(RadioXLManifestTests PRIVATE cxx_std_20)
# Sources are UTF-8: the manifest tests carry the titles a station author writes.
if(MSVC)
    target_compile_options(RadioXLManifestTests PRIVATE /utf-8)
endif()
add_test(NAME manifest COMMAND RadioXLManifestTests)
