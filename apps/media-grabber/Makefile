APP_NAME := MediaGrabber
BUNDLE_ID := app.mediagrabber.mac
DERIVED := build
APP := $(abspath $(DERIVED)/Build/Products/Debug/$(APP_NAME).app)

.DEFAULT_GOAL := run
.PHONY: generate build run

generate:
	mise exec -- tuist generate --no-open

build: generate
	xcodebuild -workspace $(APP_NAME).xcworkspace -scheme $(APP_NAME) \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED) \
		build

run: build
	@pids=`osascript -e 'tell application "System Events" to get unix id of (every process whose bundle identifier is "$(BUNDLE_ID)")' 2>/dev/null | tr ',' ' '` ; \
		if [ -n "$$pids" ]; then kill -9 $$pids; fi
	@killall -9 $(APP_NAME) >/dev/null 2>&1 || true
	@while pgrep -x $(APP_NAME) >/dev/null 2>&1; do sleep 0.05; done
	open "$(APP)"
