APP_NAME  := Clamshell
BUNDLE_ID := com.matabar.clamshell
VERSION   := 1.0.0

BUILD_DIR := build
APP       := $(BUILD_DIR)/$(APP_NAME).app
ICNS      := $(BUILD_DIR)/$(APP_NAME).icns
ARCHS     := --arch arm64 --arch x86_64
# Lazily expanded: resolving the path invokes SwiftPM, so `make clean` and
# `make help` should not pay for it.
BIN_DIR    = $(shell swift build -c release $(ARCHS) --show-bin-path)

SOURCES    = $(filter-out Sources/Clamshell/Main.swift,$(wildcard Sources/Clamshell/*.swift))

.PHONY: all build bundle icon run install uninstall zip screenshots clean help

all: bundle

help:
	@echo "make bundle     build a universal Clamshell.app into ./$(BUILD_DIR)"
	@echo "make run        build and launch it"
	@echo "make install    copy it to /Applications and launch it"
	@echo "make uninstall  quit and remove it from /Applications"
	@echo "make zip        package the bundle for distribution"
	@echo "make screenshots regenerate the README images"
	@echo "make clean      remove build products"

build:
	swift build -c release $(ARCHS)

icon: $(ICNS)

$(ICNS): Scripts/make-icon.swift
	@mkdir -p $(BUILD_DIR)
	swift Scripts/make-icon.swift $@

# Assembles a plain, self-contained .app bundle. Ad-hoc signed on purpose: the
# app is meant to be built from source, and a hardened runtime is deliberately
# left off because it blocks the AppleScript authorization path.
bundle: build $(ICNS)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN_DIR)/$(APP_NAME) $(APP)/Contents/MacOS/$(APP_NAME)
	sed 's/@VERSION@/$(VERSION)/g' Resources/Info.plist > $(APP)/Contents/Info.plist
	cp $(ICNS) $(APP)/Contents/Resources/$(APP_NAME).icns
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force --sign - --identifier $(BUNDLE_ID) $(APP)
	@echo "Built $(APP)"

run: bundle
	-@pkill -x $(APP_NAME) 2>/dev/null || true
	open $(APP)

install: bundle
	-@pkill -x $(APP_NAME) 2>/dev/null || true
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/$(APP_NAME).app
	open /Applications/$(APP_NAME).app
	@echo "Installed to /Applications/$(APP_NAME).app"

uninstall:
	-@pkill -x $(APP_NAME) 2>/dev/null || true
	rm -rf /Applications/$(APP_NAME).app
	@echo "Removed /Applications/$(APP_NAME).app"
	@if [ -f /etc/sudoers.d/clamshell ]; then \
		echo "A passwordless rule is still installed. Remove it with:"; \
		echo "  sudo rm -f /etc/sudoers.d/clamshell"; \
	fi

zip: bundle
	cd $(BUILD_DIR) && ditto -c -k --keepParent $(APP_NAME).app $(APP_NAME)-$(VERSION).zip
	@echo "Packaged $(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip"

# Regenerates the README images from the real views, so they cannot drift.
screenshots:
	@mkdir -p $(BUILD_DIR)
	swiftc -O -D DEBUG -o $(BUILD_DIR)/make-screenshots $(SOURCES) Scripts/make-screenshots.swift
	$(BUILD_DIR)/make-screenshots docs

clean:
	rm -rf .build $(BUILD_DIR)
