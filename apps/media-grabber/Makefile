APP_NAME := MediaGrabber
BUNDLE_ID := app.mediagrabber.mac
DERIVED := build
APP := $(abspath $(DERIVED)/Build/Products/Debug/$(APP_NAME).app)

.DEFAULT_GOAL := run
.PHONY: generate build run release release-patch release-minor release-major

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

# --- Release ---

CURRENT_VERSION = $(shell git tag --list 'media-grabber-v*' --sort=-v:refname \
	| head -1 | sed 's/^media-grabber-v//' | grep . || echo 0.0.0)

release-patch: BUMP := patch
release-minor: BUMP := minor
release-major: BUMP := major
release-patch release-minor release-major: release

release:
	@test -n "$(BUMP)" || { echo "pick one: make release-patch | release-minor | release-major"; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "working tree dirty — commit first"; exit 1; }
	@test "`git rev-parse --abbrev-ref HEAD`" = main || { echo "not on main"; exit 1; }
	@git fetch --quiet origin main
	@test "`git rev-parse HEAD`" = "`git rev-parse origin/main`" || { echo "local main != origin/main — push or pull first"; exit 1; }
	@next=$$(scripts/bump-version.sh $(CURRENT_VERSION) $(BUMP)) || exit 1 ; \
		echo "$(CURRENT_VERSION)  ->  $$next" ; \
		read -p "tag media-grabber-v$$next and push? [y/N] " ok ; \
		[ "$$ok" = y ] || { echo aborted; exit 1; } ; \
		git tag -a "media-grabber-v$$next" -m "media-grabber v$$next" ; \
		git push origin "media-grabber-v$$next" ; \
		echo "pushed media-grabber-v$$next — CI builds the release now"
