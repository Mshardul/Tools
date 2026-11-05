APP_NAME := MediaGrabber
BUNDLE_ID := app.mediagrabber.mac
DERIVED := build
CONFIG ?= Debug
APP := $(abspath $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app)
INSTALLED := /Applications/$(APP_NAME).app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.DEFAULT_GOAL := run
.PHONY: generate build install drop-build-app run plugin-test test lint tools release release-patch release-minor release-major

tools:
	scripts/fetch-tools.sh

generate:
	mise exec -- tuist generate --no-open

build: tools generate
	xcodebuild -workspace $(APP_NAME).xcworkspace -scheme $(APP_NAME) \
		-configuration $(CONFIG) \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED) \
		build

# make install [CONFIG=Release]; replaces the app in /Applications and removes the build copy so only one exists.
install: build
	@pids=`osascript -e 'tell application "System Events" to get unix id of (every process whose bundle identifier is "$(BUNDLE_ID)")' 2>/dev/null | tr ',' ' '` ; \
		if [ -n "$$pids" ]; then kill -9 $$pids; fi
	@killall -9 $(APP_NAME) >/dev/null 2>&1 || true
	@while pgrep -x $(APP_NAME) >/dev/null 2>&1; do sleep 0.05; done
	@test -d "$(APP)" || { echo "build product missing: $(APP)"; exit 1; }
	rm -rf "$(INSTALLED)"
	ditto "$(APP)" "$(INSTALLED)"
	$(LSREGISTER) -f "$(INSTALLED)"
	@$(MAKE) --no-print-directory drop-build-app
	open "$(INSTALLED)"

drop-build-app:
	@for config in Debug Release; do \
		app="$(abspath $(DERIVED))/Build/Products/$$config/$(APP_NAME).app" ; \
		if [ -d "$$app" ]; then $(LSREGISTER) -u "$$app" ; rm -rf "$$app" ; fi ; \
	done

run: install

PY ?= $(abspath ../../.venv/bin/python)

# Runs the bundled yt-dlp plugin's tests against the yt-dlp version pinned in requirements.txt.
plugin-test:
	$(PY) -m pip install -q -r Tests/PluginTests/requirements.txt
	$(PY) -I -B -m unittest discover -s Tests/PluginTests -p 'test_*.py'

# make test [ONLY=AppUnitTests/SomeSuite]; builds into the same build/ dir as `make`, never DerivedData.
test: plugin-test generate
	xcodebuild -workspace $(APP_NAME).xcworkspace -scheme $(APP_NAME)-Workspace \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED) \
		$(if $(ONLY),-only-testing:$(ONLY)) \
		test ; \
		status=$$? ; \
		$(MAKE) --no-print-directory drop-build-app ; \
		exit $$status

lint:
	mise exec -- swiftformat --lint .
	mise exec -- swiftlint lint --strict

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
