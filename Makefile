.PHONY: help generate prepare build install clean

DERIVED := build
APP_NAME := Meridian
SCHEME := Meridian
CONFIG := Release

help:
	@echo "Meridian — available commands:"
	@echo ""
	@echo "  make generate   Regenerate Meridian.xcodeproj from project.yml"
	@echo "  make build      Build a Release .app into $(DERIVED)/Build/Products/Release/"
	@echo "  make install    Build and copy $(APP_NAME).app into /Applications"
	@echo "  make clean      Remove generated project and build artifacts"
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
