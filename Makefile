APP_NAME = Clausona.app
BUNDLE = dist/$(APP_NAME)
BINARY = .build/release/ClausonaApp

.PHONY: build app install clean test

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/ClausonaApp
	codesign --force --sign - $(BUNDLE)

install: app
	rm -rf ~/Applications/$(APP_NAME)
	mkdir -p ~/Applications
	cp -R $(BUNDLE) ~/Applications/
	@echo "Installed to ~/Applications/$(APP_NAME)"

clean:
	rm -rf .build dist
