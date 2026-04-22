.PHONY: help generate prepare build install clean release run-debug

DERIVED := build
APP_NAME := Meridian
SCHEME := Meridian
CONFIG := Release

help:
	@echo "Meridian — available commands:"
	@echo ""
	@echo "  make generate             Regenerate Meridian.xcodeproj from project.yml"
	@echo "  make build                Build a Release .app into $(DERIVED)/Build/Products/Release/"
	@echo "  make install              Build and copy $(APP_NAME).app into /Applications"
	@echo "  make run-debug            Build + launch a Debug .app (enables the Settings Debug panel)"
	@echo "  make release VERSION=X.Y.Z  Cut a new GitHub release (tag + push + gh release create)"
	@echo "  make clean                Remove generated project and build artifacts"
	@echo ""
	@echo "Requirements : xcodegen (brew install xcodegen), Xcode 15+"

generate:
	@command -v xcodegen >/dev/null 2>&1 || { echo >&2 "xcodegen not found. Install with: brew install xcodegen"; exit 1; }
	xcodegen generate

prepare:
	@# Remove any previous build output and macOS filesystem detritus
	@# that breaks codesign (resource forks, FinderInfo, quarantine xattrs,
	@# Finder-duplicated \"Info 2.plist\" / \"Foo 3.swift\" artefacts).
	@rm -rf $(DERIVED)
	@find . -name .DS_Store -not -path "./.git/*" -delete 2>/dev/null || true
	@find Sources Resources Tests -regex ".*[[:space:]][0-9]+\..*" -not -path "*/.git/*" -delete 2>/dev/null || true
	@find . -not -path "./.git/*" -not -path "./$(DERIVED)/*" -exec xattr -c {} \; 2>/dev/null || true

build: generate prepare
	@# Build without codesigning: codesign refuses to sign any file that
	@# carries FinderInfo / resource-fork xattrs, which macOS sometimes
	@# attaches during the build itself regardless of how clean the source
	@# tree is. We'll strip and sign ourselves after.
	xcodebuild \
		-project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		build
	@echo ""
	@echo "Stripping xattrs from the built bundle..."
	@xattr -cr $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app
	@echo "Ad-hoc signing the app..."
	@codesign --force --sign - \
		--entitlements Sources/App/$(APP_NAME).entitlements \
		--deep \
		$(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app

install: build
	@echo ""
	@echo "Copying $(APP_NAME).app to /Applications/ ..."
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app /Applications/
	@echo ""
	@echo "✓ $(APP_NAME) installed."
	@echo ""
	@echo "First launch : macOS will refuse to open an unsigned app."
	@echo "In Finder, right-click /Applications/$(APP_NAME).app → Open,"
	@echo "then confirm Open in the dialog. Only needed once."
	@echo ""
	@echo "You can also run :"
	@echo "  open /Applications/$(APP_NAME).app"

clean:
	rm -rf $(DERIVED) $(APP_NAME).xcodeproj
	@echo "✓ Cleaned build artifacts and generated project"

run-debug: generate
	@# Build Debug config and launch it (keeps the Debug flags active,
	@# notably the SettingsView Debug section). Not for distribution.
	@rm -rf build-debug
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(SCHEME) \
		-configuration Debug -derivedDataPath build-debug \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
	@xattr -cr build-debug/Build/Products/Debug/$(APP_NAME).app
	@codesign --force --sign - --entitlements Sources/App/$(APP_NAME).entitlements --deep build-debug/Build/Products/Debug/$(APP_NAME).app
	@killall $(APP_NAME) 2>/dev/null || true
	@open build-debug/Build/Products/Debug/$(APP_NAME).app
	@echo "✓ Debug Meridian launched — open Settings to access the Debug panel."

# Cut a release. Usage :  make release VERSION=0.2.0
#
# Steps :
#   1. Sanity checks (gh installed, VERSION provided, working copy clean)
#   2. Bump MARKETING_VERSION in project.yml
#   3. Regenerate Meridian.xcodeproj
#   4. Commit `chore(release): vX.Y.Z`
#   5. Annotated tag `vX.Y.Z`
#   6. Push commit + tag to origin/main
#   7. gh release create vX.Y.Z --generate-notes
#
# Aborts at the first failure — no partial state. If you need to undo, the
# commit and tag are local-only until step 6.
release:
	@command -v gh >/dev/null 2>&1 || { echo >&2 "error: 'gh' not found. Install it: brew install gh — then authenticate with 'gh auth login'."; exit 1; }
	@command -v xcodegen >/dev/null 2>&1 || { echo >&2 "error: 'xcodegen' not found. Install it: brew install xcodegen"; exit 1; }
	@if [ -z "$(VERSION)" ]; then echo >&2 "error: VERSION is required. Usage: make release VERSION=0.2.0"; exit 1; fi
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo >&2 "error: VERSION must be semver MAJOR.MINOR.PATCH (got '$(VERSION)')"; exit 1; }
	@if [ -n "$$(git status --porcelain)" ]; then echo >&2 "error: working copy is not clean. Commit or stash your changes first."; git status --short >&2; exit 1; fi
	@if git rev-parse "v$(VERSION)" >/dev/null 2>&1; then echo >&2 "error: tag v$(VERSION) already exists locally."; exit 1; fi
	@echo "Cutting release v$(VERSION) …"
	@# Bump the marketing version in project.yml. We match the existing
	@# quoted form so we don't touch anything else.
	@/usr/bin/sed -i '' -E 's/^(    MARKETING_VERSION: )"[^"]*"/\1"$(VERSION)"/' project.yml
	@grep -q 'MARKETING_VERSION: "$(VERSION)"' project.yml || { echo >&2 "error: failed to bump MARKETING_VERSION in project.yml"; exit 1; }
	@xcodegen generate >/dev/null
	@# `Meridian.xcodeproj` is gitignored — only `project.yml` is staged.
	@git add project.yml
	@git commit -m "chore(release): v$(VERSION)"
	@git tag -a "v$(VERSION)" -m "v$(VERSION)"
	@git push origin main
	@git push origin "v$(VERSION)"
	@gh release create "v$(VERSION)" --title "v$(VERSION)" --generate-notes
	@echo ""
	@echo "✓ Released v$(VERSION)"
