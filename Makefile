BUILD_DIR := build
APP := $(BUILD_DIR)/Build/Products/Release/Polc.app
BUNDLE_ID := com.stephenangeloni.Polc

.PHONY: build lint test test-ui install clean

lint:
	python3 Scripts/theme_literals.py

test:
	Scripts/test-unregister-stray-builds.sh

test-ui:
	Scripts/test-settings-ui.sh

build: lint
	xcodebuild build -project Polc.xcodeproj -scheme Polc -configuration Release \
		-derivedDataPath $(BUILD_DIR) -skipPackagePluginValidation -skipMacroValidation
	Scripts/unregister-stray-builds.sh

install: build
	@if [ -d /Applications/Clop.app ] && [ "$$(defaults read /Applications/Clop.app/Contents/Info CFBundleIdentifier 2>/dev/null)" = "com.stephenangeloni.Clop" ]; then \
		echo "/Applications/Clop.app is the build Polc replaces; quit it and move it to the Bin first"; exit 1; \
	fi
	@if [ -d /Applications/Polc.app ] && [ "$$(defaults read /Applications/Polc.app/Contents/Info CFBundleIdentifier 2>/dev/null)" != "$(BUNDLE_ID)" ]; then \
		echo "/Applications/Polc.app is a different Polc build; quit and remove it first"; exit 1; \
	fi
	rm -rf /Applications/Polc.app
	cp -R $(APP) /Applications/Polc.app
	Scripts/unregister-stray-builds.sh

clean:
	rm -rf $(BUILD_DIR)
