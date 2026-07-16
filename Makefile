.PHONY: all build run clean editor typecheck swift install evals llm-edit-evals document-asset-evals api-key-store-evals personalization-evals service-install service-test

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
	cp Editor/dist/harper_wasm_slim_bg.wasm Sources/WordProcessor/Resources/harper_wasm_slim_bg.wasm
	cp Editor/dist/Harper_LICENSE.txt Sources/WordProcessor/Resources/Harper_LICENSE.txt

# Build Swift executable
swift: copy-assets
	swift build

llm-edit-evals:
	swiftc Sources/WordProcessor/Services/StringEscaping.swift Sources/WordProcessor/Services/EditTargetResolver.swift scripts/llm-edit-evals.swift -o /tmp/llm-edit-evals
	/tmp/llm-edit-evals

document-asset-evals:
	swiftc Sources/WordProcessor/Services/DocumentAssetReference.swift scripts/document-asset-evals.swift -o /tmp/document-asset-evals
	/tmp/document-asset-evals

api-key-store-evals:
	swiftc Sources/WordProcessor/Services/APIKeyStore.swift scripts/api-key-store-evals.swift -o /tmp/api-key-store-evals
	/tmp/api-key-store-evals

personalization-evals:
	PYTHONPATH=Trainer python3 -m unittest discover -s Trainer/tests -v

service-install:
	python3 -m pip install --requirement Service/requirements-dev.txt

service-test:
	PYTHONPATH=Service python3 -m pytest Service/tests
	python3 -m ruff check Service Trainer
	python3 -m ruff format --check Service Trainer

evals: llm-edit-evals document-asset-evals api-key-store-evals personalization-evals

# Build release
build: copy-assets
	swift build -c release

# Build and run
run: copy-assets
	swift build && .build/debug/WordProcessor

# Build release .app and install to /Applications
install:
	bash scripts/bundle-app.sh
	rm -rf /Applications/Shakespeare.app
	cp -R Shakespeare.app /Applications/
	rm -rf Shakespeare.app
	@echo "Installed to /Applications/Shakespeare.app"

# Clean everything
clean:
	rm -rf .build Editor/node_modules Editor/dist Service/.pytest_cache Service/.ruff_cache
	rm -f Sources/WordProcessor/Resources/editor.js Sources/WordProcessor/Resources/editor.css Sources/WordProcessor/Resources/harper-runtime.js Sources/WordProcessor/Resources/harper_wasm_slim_bg.wasm Sources/WordProcessor/Resources/Harper_LICENSE.txt
