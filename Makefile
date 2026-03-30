.PHONY: all build run clean editor swift install

all: build

# Build TipTap editor bundle
editor:
	cd Editor && npm install && node esbuild.config.mjs

# Copy JS + CSS bundles to Swift resources
copy-assets: editor
	cp Editor/dist/editor.js Sources/WordProcessor/Resources/editor.js
	cp Editor/dist/editor.css Sources/WordProcessor/Resources/editor.css

# Build Swift executable
swift: copy-assets
	swift build

# Build release
build: copy-assets
	swift build -c release

# Build and run
run: copy-assets
	swift build && .build/debug/WordProcessor

# Build release .app and install to /Applications
install: build
	bash scripts/bundle-app.sh
	rm -rf /Applications/Shakespeare.app
	cp -R Shakespeare.app /Applications/
	rm -rf Shakespeare.app
	@echo "Installed to /Applications/Shakespeare.app"

# Clean everything
clean:
	rm -rf .build Editor/node_modules Editor/dist
	rm -f Sources/WordProcessor/Resources/editor.js Sources/WordProcessor/Resources/editor.css
