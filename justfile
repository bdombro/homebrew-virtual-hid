set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

_:
    @just --list

setup:
    bun install

configure configuration="Debug":
    CXX="${CXX:-/usr/bin/clang++}" cmake -S . -B build/cmake/{{configuration}} -G Ninja \
        -DCMAKE_BUILD_TYPE={{configuration}} \
        -DENABLE_SANITIZERS={{if configuration == "Debug" { "ON" } else { "OFF" }}}

test-debug: (configure "Debug")
    cmake --build build/cmake/Debug --parallel 2
    ctest --test-dir build/cmake/Debug --output-on-failure --no-tests=error

test-release: (configure "Release")
    cmake --build build/cmake/Release --parallel 2
    ctest --test-dir build/cmake/Release --output-on-failure --no-tests=error

build: (configure "Release")
    cmake --build build/cmake/Release --target macos-input --parallel 2
    mkdir -p dist
    install -m 755 build/cmake/Release/macos-input dist/macos-input

test: test-debug test-release

alias install := install-local
alias reinstall := reinstall-local

install-local: build
    bun scripts/dev-formula.ts install

install-production:
    bun scripts/dev-formula.ts production

reinstall-local: build
    bun scripts/dev-formula.ts reinstall

uninstall:
    bun scripts/dev-formula.ts uninstall

release *ARGS:
    bun scripts/release.ts {{ARGS}}
