.PHONY: all build run clean editor typecheck swift install package evals document-asset-evals storage-layout-evals style-context-evals style-profile-evals api-key-store-evals openrouter-connection-evals language-model-wire-evals

all: build

# Install exact editor dependencies only when the lockfile changes.
Editor/node_modules/.package-lock.json: Editor/package.json Editor/package-lock.json
	cd Editor && npm ci

# Build TipTap editor bundle
editor: Editor/node_modules/.package-lock.json
	cd Editor && npm run build

typecheck: Editor/node_modules/.package-lock.json
	cd Editor && npm run typecheck

# Copy editor bundles to Swift resources
copy-assets: editor
	cp Editor/dist/editor.js Sources/WordProcessor/Resources/editor.js
	cp Editor/dist/editor.css Sources/WordProcessor/Resources/editor.css
	cp Editor/dist/harper-runtime.js Sources/WordProcessor/Resources/harper-runtime.js
	cp Editor/dist/harper-wasm-data.js Sources/WordProcessor/Resources/harper-wasm-data.js
	cp Editor/dist/THIRD_PARTY_NOTICES.txt Sources/WordProcessor/Resources/THIRD_PARTY_NOTICES.txt

# Build Swift executable
swift: copy-assets
	swift build

document-asset-evals:
	swiftc Sources/WordProcessor/Services/DocumentAssetReference.swift scripts/document-asset-evals.swift -o /tmp/document-asset-evals
	/tmp/document-asset-evals

api-key-store-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/APIKeyStore.swift scripts/api-key-store-evals.swift -o /tmp/api-key-store-evals
	/tmp/api-key-store-evals

storage-layout-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareStorage.swift scripts/storage-layout-evals.swift -o /tmp/storage-layout-evals
	/tmp/storage-layout-evals

style-context-evals:
	swiftc Sources/WordProcessor/Services/StyleContextAssembler.swift scripts/style-context-evals.swift -o /tmp/style-context-evals
	/tmp/style-context-evals

style-profile-evals:
	swiftc Sources/WordProcessor/Services/StyleProfileCompiler.swift scripts/style-profile-evals.swift -o /tmp/style-profile-evals
	/tmp/style-profile-evals

openrouter-connection-evals:
	swiftc -parse-as-library Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/InferenceSettings.swift Sources/WordProcessor/Services/OpenRouterConnectionValidator.swift scripts/openrouter-connection-evals.swift -o /tmp/openrouter-connection-evals
	/tmp/openrouter-connection-evals

language-model-wire-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/APIKeyStore.swift Sources/WordProcessor/Services/InferenceSettings.swift Sources/WordProcessor/Services/LanguageModelService.swift scripts/language-model-wire-evals.swift -o /tmp/language-model-wire-evals
	/tmp/language-model-wire-evals

evals: document-asset-evals storage-layout-evals style-context-evals style-profile-evals api-key-store-evals openrouter-connection-evals language-model-wire-evals

# Build release
build: copy-assets
	swift build -c release

# Create one self-contained app bundle under .build/package.
package:
	bash scripts/bundle-app.sh

# Build and run
run: copy-assets
	swift build && .build/debug/WordProcessor

# Build release .app and install to /Applications
install: package
	rm -rf /Applications/Shakespeare.app
	ditto .build/package/Shakespeare.app /Applications/Shakespeare.app
	@echo "Installed to /Applications/Shakespeare.app"

# Clean everything
clean:
	rm -rf .build Editor/node_modules Editor/dist
	rm -f Sources/WordProcessor/Resources/editor.js Sources/WordProcessor/Resources/editor.css Sources/WordProcessor/Resources/harper-runtime.js Sources/WordProcessor/Resources/harper-wasm-data.js Sources/WordProcessor/Resources/THIRD_PARTY_NOTICES.txt
