PROJECT := Norge360.xcodeproj
SCHEME := Norge360
DESTINATION := generic/platform=iOS Simulator
SWIFT_FORMAT := xcrun swift-format
XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
HOMEBREW_BIN_DIR ?= /opt/homebrew/bin
SWIFTLINT := $(HOMEBREW_BIN_DIR)/swiftlint
PERIPHERY := $(HOMEBREW_BIN_DIR)/periphery

# Keep SourceKit, swift-format, xcodebuild, and Periphery on the same Xcode toolchain.
export DEVELOPER_DIR := $(XCODE_DEVELOPER_DIR)
export PATH := $(HOMEBREW_BIN_DIR):$(PATH)

.PHONY: format format-check localization-check explicit-select-check lint lint-strict periphery build quality

format:
	$(SWIFT_FORMAT) format --configuration .swift-format --in-place --recursive Norge360 Norge360Tests

format-check:
	$(SWIFT_FORMAT) lint --configuration .swift-format --strict --recursive Norge360 Norge360Tests

localization-check:
	python3 scripts/check_localization.py

explicit-select-check:
	python3 scripts/check_explicit_supabase_selects.py

lint:
	$(SWIFTLINT) lint

lint-strict:
	$(SWIFTLINT) lint --strict

periphery:
	$(PERIPHERY) scan

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO build

quality: format-check localization-check explicit-select-check lint-strict build
