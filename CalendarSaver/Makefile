NAME        := CalendarSaver
SOURCES     := CalendarSaverView.swift Dashboard.swift Models.swift
BUILD_DIR   := build
BUNDLE      := $(BUILD_DIR)/$(NAME).saver
BINARY      := $(BUNDLE)/Contents/MacOS/$(NAME)
INSTALL_DIR := $(HOME)/Library/Screen Savers
TARGET      := arm64-apple-macos14

.PHONY: build install reload uninstall clean

build: $(BUNDLE)

$(BUNDLE): $(SOURCES) Info.plist
	@mkdir -p "$(BUNDLE)/Contents/MacOS"
	@mkdir -p "$(BUNDLE)/Contents/Resources"
	swiftc \
		-module-name $(NAME) \
		-target $(TARGET) \
		-O \
		-Xlinker -bundle \
		-framework ScreenSaver \
		-framework AppKit \
		-framework SwiftUI \
		-o "$(BINARY)" \
		$(SOURCES)
	cp Info.plist "$(BUNDLE)/Contents/Info.plist"
	codesign --force --sign - --timestamp=none "$(BUNDLE)"
	@echo "Built: $(BUNDLE)"

install: build
	@rm -rf "$(INSTALL_DIR)/$(NAME).saver"
	@mkdir -p "$(INSTALL_DIR)"
	cp -R "$(BUNDLE)" "$(INSTALL_DIR)/"
	@echo "Installed: $(INSTALL_DIR)/$(NAME).saver"

reload: install
	@pkill -9 -f legacyScreenSaver 2>/dev/null || true
	@echo "Killed cached legacyScreenSaver — next screensaver activation will load the new binary"
	@echo "Triggering helper to populate fresh events.json…"
	@"$(HOME)/Library/Application Support/CalendarSaver/bin/calendar-refresh" || echo "(helper not installed yet; LaunchAgent will fill it in within 60s)"

uninstall:
	@rm -rf "$(INSTALL_DIR)/$(NAME).saver"
	@echo "Removed: $(INSTALL_DIR)/$(NAME).saver"

clean:
	rm -rf $(BUILD_DIR)
