# Minimal .saver bundle builder. No Xcode required; uses CLT swiftc.

NAME        := CalendarSaverTest
SOURCE      := $(NAME)View.swift
BUILD_DIR   := build
BUNDLE      := $(BUILD_DIR)/$(NAME).saver
BINARY      := $(BUNDLE)/Contents/MacOS/$(NAME)
INSTALL_DIR := $(HOME)/Library/Screen Savers
TARGET      := arm64-apple-macos14

.PHONY: build install uninstall clean

build: $(BUNDLE)

$(BUNDLE): $(SOURCE) Info.plist
	@mkdir -p "$(BUNDLE)/Contents/MacOS"
	@mkdir -p "$(BUNDLE)/Contents/Resources"
	swiftc \
		-module-name $(NAME) \
		-target $(TARGET) \
		-O \
		-Xlinker -bundle \
		-framework ScreenSaver \
		-framework EventKit \
		-framework AppKit \
		-o "$(BINARY)" \
		$(SOURCE)
	cp Info.plist "$(BUNDLE)/Contents/Info.plist"
	codesign --force --sign - --timestamp=none "$(BUNDLE)"
	@echo "Built: $(BUNDLE)"

install: build
	@rm -rf "$(INSTALL_DIR)/$(NAME).saver"
	@mkdir -p "$(INSTALL_DIR)"
	cp -R "$(BUNDLE)" "$(INSTALL_DIR)/"
	@echo "Installed: $(INSTALL_DIR)/$(NAME).saver"

uninstall:
	@rm -rf "$(INSTALL_DIR)/$(NAME).saver"
	@echo "Removed:   $(INSTALL_DIR)/$(NAME).saver"

clean:
	rm -rf $(BUILD_DIR)
