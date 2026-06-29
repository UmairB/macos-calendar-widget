NAME        := calendar-refresh
SOURCE      := CalendarRefresh.swift
BUILD_DIR   := build
BINARY      := $(BUILD_DIR)/$(NAME)
INSTALL_DIR := $(HOME)/Library/Application Support/CalendarSaver/bin
PLIST_DEST  := $(HOME)/Library/LaunchAgents/com.umairb.calendarrefresh.plist
TARGET      := arm64-apple-macos14

.PHONY: build install run load unload uninstall clean

build: $(BINARY)

$(BINARY): $(SOURCE) Info.plist
	@mkdir -p $(BUILD_DIR)
	swiftc \
		-target $(TARGET) \
		-O \
		-framework EventKit \
		-framework Foundation \
		-Xlinker -sectcreate \
		-Xlinker __TEXT \
		-Xlinker __info_plist \
		-Xlinker Info.plist \
		-o $(BINARY) \
		$(SOURCE)
	codesign --force --sign - --timestamp=none $(BINARY)
	@echo "Built: $(BINARY)"

install: build
	@mkdir -p "$(INSTALL_DIR)"
	cp $(BINARY) "$(INSTALL_DIR)/$(NAME)"
	@echo "Installed: $(INSTALL_DIR)/$(NAME)"

run: install
	"$(INSTALL_DIR)/$(NAME)"

load: install
	@sed "s|@@HOME@@|$(HOME)|g" com.umairb.calendarrefresh.plist.template > "$(PLIST_DEST)"
	@launchctl bootout "gui/$$(id -u)/com.umairb.calendarrefresh" 2>/dev/null || true
	launchctl bootstrap "gui/$$(id -u)" "$(PLIST_DEST)"
	@echo "Loaded launch agent: $(PLIST_DEST)"

unload:
	@launchctl bootout "gui/$$(id -u)/com.umairb.calendarrefresh" 2>/dev/null || true
	@rm -f "$(PLIST_DEST)"
	@echo "Unloaded launch agent"

uninstall: unload
	@rm -f "$(INSTALL_DIR)/$(NAME)"
	@echo "Removed: $(INSTALL_DIR)/$(NAME)"

clean:
	rm -rf $(BUILD_DIR)
