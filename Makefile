.PHONY: all build run clean editor editor-tests typecheck privacy-check release-script-check website-check check swift install update package deploy-site release evals document-asset-evals storage-layout-evals style-context-evals style-profile-evals writing-quality-evals live-writing-evals api-key-store-evals openrouter-connection-evals model-availability-evals language-model-wire-evals

all: build

# Install exact editor dependencies only when the lockfile changes.
Editor/node_modules/.package-lock.json: Editor/package.json Editor/package-lock.json
	cd Editor && npm ci

Website/node_modules/.package-lock.json: Website/package.json Website/package-lock.json
	cd Website && npm ci

# Build TipTap editor bundle
editor: Editor/node_modules/.package-lock.json
	cd Editor && npm run build

typecheck: Editor/node_modules/.package-lock.json
	cd Editor && npm run typecheck

editor-tests: Editor/node_modules/.package-lock.json
	cd Editor && npm test

privacy-check:
	bash scripts/verify-source-privacy.sh

release-script-check:
	bash -n scripts/verify-release-archive.sh scripts/verify-public-release.sh scripts/install-release-archive.sh scripts/update-from-public-download.sh scripts/release.sh

website-check: Website/node_modules/.package-lock.json
	cd Website && npm run build

# Full deterministic validation. This replaces automatic GitHub-hosted CI.
check: privacy-check typecheck evals website-check build

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
	swiftc Sources/WordProcessor/Services/StyleProfileCompiler.swift Sources/WordProcessor/Services/StyleProfileDraftStore.swift scripts/style-profile-evals.swift -o /tmp/style-profile-evals
	/tmp/style-profile-evals

writing-quality-evals:
	swiftc Sources/WordProcessor/Services/AmbientReviewContract.swift scripts/writing-quality-evals.swift -o /tmp/writing-quality-evals
	/tmp/writing-quality-evals

# Optional and cost-capped: three requests, one selected model, 768 output tokens each.
live-writing-evals:
	swiftc -parse-as-library Sources/WordProcessor/Services/AmbientReviewContract.swift scripts/live-writing-quality-evals.swift -o /tmp/live-writing-quality-evals
	/tmp/live-writing-quality-evals

openrouter-connection-evals:
	swiftc -parse-as-library Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/InferenceSettings.swift Sources/WordProcessor/Services/OpenRouterConnectionValidator.swift scripts/openrouter-connection-evals.swift -o /tmp/openrouter-connection-evals
	/tmp/openrouter-connection-evals

model-availability-evals:
	swiftc -parse-as-library Sources/WordProcessor/Services/OpenRouterModelAvailabilityService.swift scripts/model-availability-evals.swift -o /tmp/model-availability-evals
	/tmp/model-availability-evals

language-model-wire-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/APIKeyStore.swift Sources/WordProcessor/Services/InferenceSettings.swift Sources/WordProcessor/Services/LanguageModelService.swift scripts/language-model-wire-evals.swift -o /tmp/language-model-wire-evals
	/tmp/language-model-wire-evals

evals: release-script-check editor-tests document-asset-evals storage-layout-evals style-context-evals style-profile-evals writing-quality-evals api-key-store-evals openrouter-connection-evals model-availability-evals language-model-wire-evals

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

# Install the exact signed and notarized app currently served by the website.
update:
	bash scripts/update-from-public-download.sh

# Validate the site and deploy it to Cloudflare. R2 releases stay independent.
deploy-site: Website/node_modules/.package-lock.json
	cd Website && npm run build && npx wrangler deploy --config wrangler.jsonc

# Build, sign, notarize, verify, and publish one release from this Mac.
release:
	bash scripts/release.sh

# Clean everything
clean:
	rm -rf .build Editor/node_modules Editor/dist Website/node_modules
	rm -f Sources/WordProcessor/Resources/editor.js Sources/WordProcessor/Resources/editor.css Sources/WordProcessor/Resources/harper-runtime.js Sources/WordProcessor/Resources/harper-wasm-data.js Sources/WordProcessor/Resources/THIRD_PARTY_NOTICES.txt
