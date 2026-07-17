.PHONY: all build run clean editor editor-tests typecheck privacy-check delivery-contract-check release-script-check website-check cloud-ci check swift install update package deploy-site release-readiness release evals document-asset-evals document-package-safety-evals canonical-document-evals document-state-evals storage-layout-evals style-context-evals chat-context-evals style-profile-evals ledger-retention-evals writing-quality-evals live-writing-evals api-key-store-evals openrouter-connection-evals model-availability-evals language-model-wire-evals focus-mode-escape-evals

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

delivery-contract-check:
	bash scripts/verify-delivery-contract.sh

release-script-check: delivery-contract-check
	bash -n scripts/verify-release-archive.sh scripts/verify-public-release.sh scripts/install-release-archive.sh scripts/update-from-public-download.sh scripts/verify-release-provenance.sh scripts/run-wrangler.sh scripts/release-readiness.sh scripts/release.sh

website-check: Website/node_modules/.package-lock.json
	cd Website && npm run build

# Portable, zero-credential checks run by Cloudflare for every main-branch push.
# Swift/AppKit validation remains the local `make check` gate before pushing.
cloud-ci: privacy-check release-script-check typecheck editor-tests website-check

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

document-package-safety-evals:
	swiftc Sources/WordProcessor/Services/PackageFileSafety.swift scripts/document-package-safety-evals.swift -o /tmp/document-package-safety-evals
	/tmp/document-package-safety-evals

canonical-document-evals:
	swiftc Sources/WordProcessor/Services/CanonicalDocumentValidator.swift scripts/canonical-document-evals.swift -o /tmp/canonical-document-evals
	/tmp/canonical-document-evals

document-state-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/DocumentAssetReference.swift Sources/WordProcessor/Services/PackageFileSafety.swift Sources/WordProcessor/Services/CanonicalDocumentValidator.swift Sources/WordProcessor/Services/DocumentFileStore.swift Sources/WordProcessor/Models/Document.swift scripts/document-state-evals.swift -o /tmp/document-state-evals
	/tmp/document-state-evals

api-key-store-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/APIKeyStore.swift scripts/api-key-store-evals.swift -o /tmp/api-key-store-evals
	/tmp/api-key-store-evals

storage-layout-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareStorage.swift scripts/storage-layout-evals.swift -o /tmp/storage-layout-evals
	/tmp/storage-layout-evals

style-context-evals:
	swiftc Sources/WordProcessor/Services/StyleContextAssembler.swift scripts/style-context-evals.swift -o /tmp/style-context-evals
	/tmp/style-context-evals

chat-context-evals:
	swiftc Sources/WordProcessor/Services/ChatDocumentContextAssembler.swift scripts/chat-context-evals.swift -o /tmp/chat-context-evals
	/tmp/chat-context-evals

style-profile-evals:
	swiftc Sources/WordProcessor/Services/PackageFileSafety.swift Sources/WordProcessor/Services/StyleProfileCompiler.swift Sources/WordProcessor/Services/StyleProfileDraftStore.swift scripts/style-profile-evals.swift -o /tmp/style-profile-evals
	/tmp/style-profile-evals

ledger-retention-evals:
	swiftc Sources/WordProcessor/Services/PersonalizationLedgerRetention.swift scripts/ledger-retention-evals.swift -o /tmp/ledger-retention-evals
	/tmp/ledger-retention-evals

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

focus-mode-escape-evals:
	swiftc -parse-as-library Sources/WordProcessor/Views/FocusModeEscapeMonitor.swift scripts/focus-mode-escape-evals.swift -o /tmp/focus-mode-escape-evals
	/tmp/focus-mode-escape-evals

evals: release-script-check editor-tests document-asset-evals document-package-safety-evals canonical-document-evals document-state-evals storage-layout-evals style-context-evals chat-context-evals style-profile-evals ledger-retention-evals writing-quality-evals api-key-store-evals openrouter-connection-evals model-availability-evals language-model-wire-evals focus-mode-escape-evals

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

# Recovery-only production deploy. Routine site delivery is push-based in Cloudflare.
deploy-site: Website/node_modules/.package-lock.json
	@if [ "$$(git branch --show-current)" != "main" ] || [ -n "$$(git status --porcelain --untracked-files=normal)" ]; then \
		echo "Deploy the production site only from a clean main branch." >&2; exit 1; \
	fi
	@git fetch --quiet origin main
	@if [ "$$(git rev-parse HEAD)" != "$$(git rev-parse origin/main)" ]; then \
		echo "Local main must exactly match origin/main." >&2; exit 1; \
	fi
	cd Website && npm run build
	bash scripts/run-wrangler.sh deploy

# Build, sign, notarize, verify, and publish one release from this Mac.
release-readiness:
	bash scripts/release-readiness.sh

release:
	bash scripts/release.sh

# Clean everything
clean:
	rm -rf .build Editor/node_modules Editor/dist Website/node_modules
	rm -f Sources/WordProcessor/Resources/editor.js Sources/WordProcessor/Resources/editor.css Sources/WordProcessor/Resources/harper-runtime.js Sources/WordProcessor/Resources/harper-wasm-data.js Sources/WordProcessor/Resources/THIRD_PARTY_NOTICES.txt
