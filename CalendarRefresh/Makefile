NAME        := calendar-refresh
SOURCES     := CalendarRefresh.swift Location.swift
BUILD_DIR   := build
BINARY      := $(BUILD_DIR)/$(NAME)
INSTALL_DIR := $(HOME)/Library/Application Support/CalendarSaver/bin
LABEL       := com.example.calendarrefresh
PLIST_DEST  := $(HOME)/Library/LaunchAgents/$(LABEL).plist
PLIST_TMPL  := $(LABEL).plist.template
TARGET      := arm64-apple-macos14

.PHONY: build install run load unload uninstall clean

build: $(BINARY)

$(BINARY): $(SOURCES) Info.plist
	@if [ ! -f Location.swift ]; then \
		echo "ERROR: Location.swift is missing. Copy Location.swift.example to Location.swift and edit it with your lat/lon."; \
		exit 1; \
	fi
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
		$(SOURCES)
	codesign --force --sign - --timestamp=none $(BINARY)
	@echo "Built: $(BINARY)"

install: build
	@mkdir -p "$(INSTALL_DIR)"
	cp $(BINARY) "$(INSTALL_DIR)/$(NAME)"
	@echo "Installed: $(INSTALL_DIR)/$(NAME)"

run: install
	"$(INSTALL_DIR)/$(NAME)"

load: install
	@sed "s|@@HOME@@|$(HOME)|g" $(PLIST_TMPL) > "$(PLIST_DEST)"
	@launchctl bootout "gui/$$(id -u)/$(LABEL)" 2>/dev/null || true
	launchctl bootstrap "gui/$$(id -u)" "$(PLIST_DEST)"
	@echo "Loaded launch agent: $(PLIST_DEST)"

unload:
	@launchctl bootout "gui/$$(id -u)/$(LABEL)" 2>/dev/null || true
	@rm -f "$(PLIST_DEST)"
	@echo "Unloaded launch agent"

uninstall: unload
	@rm -f "$(INSTALL_DIR)/$(NAME)"
	@echo "Removed: $(INSTALL_DIR)/$(NAME)"

clean:
	rm -rf $(BUILD_DIR)
