APP_NAME = Clausona.app
BUNDLE = dist/$(APP_NAME)
BINARY = .build/release/ClausonaApp
DMG = dist/Clausona.dmg

.PHONY: build app install dmg clean test

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/ClausonaApp
	codesign --force --sign - $(BUNDLE)

install: app
	rm -rf ~/Applications/$(APP_NAME)
	mkdir -p ~/Applications
	cp -R $(BUNDLE) ~/Applications/
	@echo "Installed to ~/Applications/$(APP_NAME)"

# Drag-to-Applications disk image for distribution.
dmg: app
	rm -f $(DMG)
	rm -rf dist/dmg && mkdir -p dist/dmg
	cp -R $(BUNDLE) dist/dmg/
	ln -s /Applications dist/dmg/Applications
	hdiutil create -volname "Clausona" -srcfolder dist/dmg -ov -format UDZO $(DMG)
	rm -rf dist/dmg
	@echo "Built $(DMG)"

clean:
	rm -rf .build dist
