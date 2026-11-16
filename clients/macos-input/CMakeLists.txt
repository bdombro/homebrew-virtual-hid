cmake_minimum_required(VERSION 3.31)
if(NOT CMAKE_HOST_APPLE)
    message(FATAL_ERROR "macos-input requires macOS")
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 13.0)
endif()
if(NOT CMAKE_OSX_SYSROOT)
    execute_process(COMMAND xcrun --show-sdk-path
        OUTPUT_VARIABLE CMAKE_OSX_SYSROOT OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY)
endif()
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../../VERSION" MACOS_INPUT_VERSION LIMIT_COUNT 1)
string(STRIP "${MACOS_INPUT_VERSION}" MACOS_INPUT_VERSION)
project(macos_input VERSION "${MACOS_INPUT_VERSION}" LANGUAGES CXX OBJC)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/../../VERSION")
set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
include(CTest)
include(CheckIPOSupported)
option(ENABLE_SANITIZERS "Enable address and undefined behavior sanitizers" OFF)
if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    message(FATAL_ERROR "Clang/libc++ required")
endif()
add_library(app_options INTERFACE)
if(APPLE)
    execute_process(COMMAND "${CMAKE_CXX_COMPILER}" -print-file-name=c++/libc++.a
        OUTPUT_VARIABLE libcxx_a OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
    cmake_path(NORMAL_PATH libcxx_a)
    if(NOT EXISTS "${libcxx_a}")
        message(FATAL_ERROR "Static libc++.a not found via ${CMAKE_CXX_COMPILER} (got '${libcxx_a}'); use llvm@23")
    endif()
    cmake_path(GET libcxx_a PARENT_PATH libcxx_dir)
    target_compile_options(app_options INTERFACE
        "$<$<COMPILE_LANGUAGE:CXX>:-stdlib=libc++>"
        -ftrivial-auto-var-init=zero -Wall -Wextra -Wpedantic)
    target_link_options(app_options INTERFACE
        -nostdlib++ "${libcxx_dir}/libc++.a" "${libcxx_dir}/libc++abi.a"
        -Wl,-exported_symbols_list,/dev/null)
endif()
target_compile_definitions(app_options INTERFACE
    _LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST)
if(ENABLE_SANITIZERS)
    target_compile_options(app_options INTERFACE
        -g -fsanitize=address,undefined -fno-sanitize-recover=undefined)
    target_link_options(app_options INTERFACE -fsanitize=address,undefined)
endif()
check_ipo_supported(RESULT HAVE_IPO OUTPUT IPO_ERROR)
if(NOT HAVE_IPO)
    message(FATAL_ERROR "Release IPO required: ${IPO_ERROR}")
endif()
include(FetchContent)
FetchContent_Declare(karabiner
    GIT_REPOSITORY https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice.git
    GIT_TAG 212a0f660702e33a3874895c4db991061e68e0e2
    GIT_SUBMODULES ""
    SOURCE_SUBDIR include
)
FetchContent_MakeAvailable(karabiner)
set(autorelease_pool_impl
    "${karabiner_SOURCE_DIR}/vendor/vendor/src/pqrs/osx/autorelease_pool/PQRSOSXAutoreleasePoolImpl.m")
add_executable(macos-input src/main.cpp "${autorelease_pool_impl}")
# Embed resources/driver-setup.txt (the single source for setup text) as a raw string.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/resources/driver-setup.txt")
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/resources/driver-setup.txt" MACOS_INPUT_DRIVER_SETUP)
file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/generated/driver_setup.hpp"
    CONTENT "#pragma once\ninline constexpr const char* driver_setup_text = R\"setup(@MACOS_INPUT_DRIVER_SETUP@)setup\";\n"
    @ONLY)
target_include_directories(macos-input PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
target_compile_definitions(macos-input PRIVATE MACOS_INPUT_VERSION="${PROJECT_VERSION}")
set_source_files_properties("${autorelease_pool_impl}" PROPERTIES COMPILE_OPTIONS -fno-objc-arc)
target_include_directories(macos-input SYSTEM PRIVATE
    "${karabiner_SOURCE_DIR}/include"
    "${karabiner_SOURCE_DIR}/vendor/vendor/include"
)
target_link_libraries(macos-input PRIVATE
    app_options "-framework Foundation" "-framework CoreGraphics" "-framework IOKit" objc
)
set_target_properties(macos-input PROPERTIES
    INTERPROCEDURAL_OPTIMIZATION_RELEASE ON
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/build/bin")
install(TARGETS macos-input RUNTIME DESTINATION bin)
if(BUILD_TESTING)
    find_package(slimr-test CONFIG REQUIRED)
    add_test(NAME cli COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/tests/cli.sh"
        "$<TARGET_FILE:macos-input>")
    add_executable(macos_input_test tests/test_main.cpp)
    target_include_directories(macos_input_test PRIVATE src tests)
    target_link_libraries(macos_input_test PRIVATE slimr::test app_options)
    set_target_properties(macos_input_test PROPERTIES INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)
    add_test(NAME mouse COMMAND macos_input_test)
    set_tests_properties(cli PROPERTIES TIMEOUT 20)
    set_tests_properties(mouse PROPERTIES TIMEOUT 120
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        ENVIRONMENT "BUGSINK_DSN=;TMPDIR=${CMAKE_BINARY_DIR}")
endif()
