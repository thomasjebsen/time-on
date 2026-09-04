APP_NAME = TimeOn
BUILD_DIR = .build/release
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

# Pure-Foundation sources compiled directly into the analytics test binary.
ANALYTICS_SOURCES = Sources/TimeOn/SessionEntry.swift Sources/TimeOn/SessionAnalytics.swift
ANALYTICS_TEST_BIN = .build/analytics_tests

.PHONY: build clean install uninstall app test test-session test-analytics

build:
	swift build -c release

app: build
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

install: app
	cp -r "$(APP_BUNDLE)" /Applications/$(APP_NAME).app
	@echo "Installed to /Applications/$(APP_NAME).app"

uninstall:
	rm -rf /Applications/$(APP_NAME).app
	@echo "Uninstalled $(APP_NAME)"

clean:
	swift package clean
	rm -rf .build

run: app
	open "$(APP_BUNDLE)"

test: test-session test-analytics

# SessionManager idle/break/pomodoro tests (script with a mirror copy of SessionManager).
test-session:
	swift Tests/run_tests.swift

# SessionAnalytics tests compiled against the real source files.
test-analytics:
	@mkdir -p .build
	swiftc -parse-as-library $(ANALYTICS_SOURCES) Tests/analytics_tests.swift -o $(ANALYTICS_TEST_BIN)
	$(ANALYTICS_TEST_BIN)
