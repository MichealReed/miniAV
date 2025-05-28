# Set the shell explicitly for UNIX-like systems
SHELL := /bin/bash

# Detect the operating system
ifeq ($(OS),Windows_NT)
	DETECTED_OS := Windows
	DEL_CMD := del /s /q
	RMDIR_CMD := rmdir /s /q
	MKDIR_CMD := mkdir
	SLASH := \\
	EXE_EXT := .exe
	TEST_BIN_DIR_SUFFIX := Debug$(SLASH)
else
	DETECTED_OS := $(shell uname)
	DEL_CMD := rm -rf
	RMDIR_CMD := rm -rf
	MKDIR_CMD := mkdir -p
	SLASH := /
	EXE_EXT :=
	TEST_BIN_DIR_SUFFIX :=
endif

PLATFORM_INTERFACE_DIR := ./miniav_platform_interface/
FFI_DIR := .$(SLASH)miniav_ffi$(SLASH)
WEB_DIR := .$(SLASH)miniav_web$(SLASH)
miniav_DIR := .$(SLASH)miniav$(SLASH)
EXAMPLE_DIR := .$(SLASH)miniav$(SLASH)example$(SLASH)
SRC_DIR := .$(SLASH)miniav_ffi$(SLASH)miniav_c$(SLASH)
BUILD_DIR := .$(SLASH)miniav_ffi$(SLASH)miniav_c$(SLASH)build$(SLASH)
BUILD_WEB_DIR := .$(SLASH)miniav_ffi$(SLASH)src$(SLASH)build_web$(SLASH)

TEST_BIN_DIR_BASE := $(BUILD_DIR)bin$(SLASH)
TEST_BIN_DIR := $(TEST_BIN_DIR_BASE)$(TEST_BIN_DIR_SUFFIX)

VERSION ?= 1.0.0

.PHONY: default pubspec_local pubspec_release clean run run_device run_web ffigen build_weblib build_ffilib clean_weblib clean_ffilib test_screen test_loopback test_camera test_audio help

default: run

pubspec_local:
	@echo "󰐊 Switching our pubspecs for local dev with version ${VERSION}."
	@python update_pubspecs.py ${VERSION}

pubspec_release:
	@echo "󰐊 Switching our pubspecs for release with version ${VERSION}."
	@python update_pubspecs.py ${VERSION} --release

clean:
	@echo "󰃢 Cleaning Example."
	@cd $(EXAMPLE_DIR) && flutter clean

run:
ifeq ($(DETECTED_OS), Windows)
	@echo "󰐊 Running example on Windows..."
	@cd $(EXAMPLE_DIR) && cmd /c flutter run -d Windows
else ifeq ($(DETECTED_OS), Linux)
	@echo "󰐊 Running example on $(DETECTED_OS)..."
	@cd $(EXAMPLE_DIR) && flutter run -d Linux
else ifeq ($(DETECTED_OS), Darwin)
	@echo "󰐊 Running example on $(DETECTED_OS)..."
	@cd $(EXAMPLE_DIR) && flutter run -d MacOS
else
	@echo "Unsupported OS: $(DETECTED_OS)"
endif

run_device:
	@echo "󰐊 Running example on device..."
	@cd $(EXAMPLE_DIR) && flutter run

run_web: build_weblib
	@echo "󰐊 Running web example..."
	@cd $(EXAMPLE_DIR) && flutter run -d chrome --web-browser-flag "--enable-features=SharedArrayBuffer" --web-browser-flag "--enable-unsafe-webgpu" --web-browser-flag "--disable-dawn-features=diallow_unsafe_apis"

ffigen:
	@echo "Generating dart ffi bindings..."
	@cd $(FFI_DIR) && dart run ffigen

build_weblib:
	@echo "Building ffi lib to web via emscripten..."
	@cd $(BUILD_WEB_DIR) && emcmake cmake .. && cmake --build .

build_ffilib:
	@echo "Building ffi lib to native..."
	@cd $(BUILD_DIR) && cmake cmake .. --fresh && cmake --build .

# Removed the first definition of clean_weblib that was here.

clean_ffilib:
	@echo "Cleaning lib dir..."
	@$(RMDIR_CMD) "$(BUILD_DIR)build_android" 2>nul || true
	@$(RMDIR_CMD) "$(BUILD_DIR)build_win" 2>nul || true
	@$(RMDIR_CMD) "$(BUILD_DIR)build_unix" 2>nul || true

clean_weblib:
	@echo "Cleaning web lib dir..."
	@$(RMDIR_CMD) "$(BUILD_WEB_DIR)" 2>nul || true
	@$(MKDIR_CMD) "$(BUILD_WEB_DIR)"

# Define test executable names
EXEC_NAME_SCREEN_CAPTURE := test_screen_capture
EXEC_NAME_LOOPBACK := test_loopback_capture
EXEC_NAME_CAMERA := test_camera_capture
EXEC_NAME_AUDIO := test_audio_capture

# Test execution targets
test_screen: build_ffilib
	@echo "󰙨 Running screen capture test ($(EXEC_NAME_SCREEN_CAPTURE))..."
ifeq ($(DETECTED_OS), Windows)
	@if exist "$(TEST_BIN_DIR)$(EXEC_NAME_SCREEN_CAPTURE)$(EXE_EXT)" ( \
		"$(TEST_BIN_DIR)$(EXEC_NAME_SCREEN_CAPTURE)$(EXE_EXT)" \
	) else ( \
		echo Test executable not found: "$(TEST_BIN_DIR)$(EXEC_NAME_SCREEN_CAPTURE)$(EXE_EXT)" && exit /b 1 \
	)
else
	@if [ -f "$(TEST_BIN_DIR)$(EXEC_NAME_SCREEN_CAPTURE)$(EXE_EXT)" ]; then \
		"$(TEST_BIN_DIR)$(EXEC_NAME_SCREEN_CAPTURE)$(EXE_EXT)"; \
	else \
		echo "Test executable not found: $(TEST_BIN_DIR)$(EXEC_NAME_SCREEN_CAPTURE)$(EXE_EXT)" && exit 1; \
	fi
endif

test_loopback: build_ffilib
	@echo "󰕾 Running loopback test ($(EXEC_NAME_LOOPBACK))..."
ifeq ($(DETECTED_OS), Windows)
	@if exist "$(TEST_BIN_DIR)$(EXEC_NAME_LOOPBACK)$(EXE_EXT)" ( \
		"$(TEST_BIN_DIR)$(EXEC_NAME_LOOPBACK)$(EXE_EXT)" \
	) else ( \
		echo Test executable not found: "$(TEST_BIN_DIR)$(EXEC_NAME_LOOPBACK)$(EXE_EXT)" && exit /b 1 \
	)
else
	@if [ -f "$(TEST_BIN_DIR)$(EXEC_NAME_LOOPBACK)$(EXE_EXT)" ]; then \
		"$(TEST_BIN_DIR)$(EXEC_NAME_LOOPBACK)$(EXE_EXT)"; \
	else \
		echo "Test executable not found: $(TEST_BIN_DIR)$(EXEC_NAME_LOOPBACK)$(EXE_EXT)" && exit 1; \
	fi
endif

test_camera: build_ffilib
	@echo "󰄀 Running camera test ($(EXEC_NAME_CAMERA))..."
ifeq ($(DETECTED_OS), Windows)
	@if exist "$(TEST_BIN_DIR)$(EXEC_NAME_CAMERA)$(EXE_EXT)" ( \
		"$(TEST_BIN_DIR)$(EXEC_NAME_CAMERA)$(EXE_EXT)" \
	) else ( \
		echo Test executable not found: "$(TEST_BIN_DIR)$(EXEC_NAME_CAMERA)$(EXE_EXT)" && exit /b 1 \
	)
else
	@if [ -f "$(TEST_BIN_DIR)$(EXEC_NAME_CAMERA)$(EXE_EXT)" ]; then \
		"$(TEST_BIN_DIR)$(EXEC_NAME_CAMERA)$(EXE_EXT)"; \
	else \
		echo "Test executable not found: $(TEST_BIN_DIR)$(EXEC_NAME_CAMERA)$(EXE_EXT)" && exit 1; \
	fi
endif

test_audio: build_ffilib
	@echo "󰓃 Running audio test ($(EXEC_NAME_AUDIO))..."
ifeq ($(DETECTED_OS), Windows)
	@if exist "$(TEST_BIN_DIR)$(EXEC_NAME_AUDIO)$(EXE_EXT)" ( \
		"$(TEST_BIN_DIR)$(EXEC_NAME_AUDIO)$(EXE_EXT)" \
	) else ( \
		echo Test executable not found: "$(TEST_BIN_DIR)$(EXEC_NAME_AUDIO)$(EXE_EXT)" && exit /b 1 \
	)
else
	@if [ -f "$(TEST_BIN_DIR)$(EXEC_NAME_AUDIO)$(EXE_EXT)" ]; then \
		"$(TEST_BIN_DIR)$(EXEC_NAME_AUDIO)$(EXE_EXT)"; \
	else \
		echo "Test executable not found: $(TEST_BIN_DIR)$(EXEC_NAME_AUDIO)$(EXE_EXT)" && exit 1; \
	fi
endif

help:
	@echo ** Available Commands **
	@echo *  make pubspec_local: Switches pubspecs for local dev."
	@echo *  make pubspec_release: Switches pubspecs for release."
	@echo *  make clean: Cleans the example project."
	@echo *  make run: Runs the example project on current OS."
	@echo *  make run_device: Runs the example project on chosen device."
	@echo *  make run_web: Runs the web example project."
	@echo *  make ffigen: Generates dart ffi bindings."
	@echo *  make build_weblib: Builds the ffi lib to web via emscripten."
	@echo *  make build_ffilib: Builds the ffi lib to native."
	@echo *  make test_screen: Runs the screen capture test."
	@echo *  make test_loopback: Runs the loopback test."
	@echo *  make test_camera: Runs the camera test."
	@echo *  make test_audio: Runs the audio test."
	@echo *  make clean_weblib: Cleans the web lib."
	@echo *  make clean_ffilib: Cleans the native lib."
	@echo *  make help: Shows this help message."