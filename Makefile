.PHONY: all build run clean editor swift install llm-edit-evals

all: build

# Build TipTap editor bundle
editor:
	cd Editor && npm install && node esbuild.config.mjs

# Copy editor bundles to Swift resources
copy-assets: editor
	cp Editor/dist/editor.js Sources/WordProcessor/Resources/editor.js
	cp Editor/dist/editor.css Sources/WordProcessor/Resources/editor.css
	cp Editor/dist/harper-runtime.js Sources/WordProcessor/Resources/harper-runtime.js
	cp Editor/dist/harper_wasm_slim_bg.wasm Sources/WordProcessor/Resources/harper_wasm_slim_bg.wasm
	cp Editor/dist/Harper_LICENSE.txt Sources/WordProcessor/Resources/Harper_LICENSE.txt

# Build Swift executable
swift: copy-assets
	swift build

llm-edit-evals:
	swiftc Sources/WordProcessor/Services/EditTargetResolver.swift scripts/llm-edit-evals.swift -o /tmp/llm-edit-evals
	/tmp/llm-edit-evals

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
	rm -f Sources/WordProcessor/Resources/editor.js Sources/WordProcessor/Resources/editor.css Sources/WordProcessor/Resources/harper-runtime.js Sources/WordProcessor/Resources/harper_wasm_slim_bg.wasm Sources/WordProcessor/Resources/Harper_LICENSE.txt
