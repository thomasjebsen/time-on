PREFIX ?= /usr/local
APP_NAME = TimeOn
BUILD_DIR = .build/release
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR = $(PREFIX)/bin

.PHONY: build clean install uninstall app

build:
	swift build -c release

app: build
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@echo "Built $(APP_BUNDLE)"

install: app
	mkdir -p "$(INSTALL_DIR)"
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
