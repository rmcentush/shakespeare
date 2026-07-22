.PHONY: all build strict-concurrency-check run clean editor editor-tests typecheck privacy-check provenance-check check swift install package evals document-asset-evals document-package-safety-evals canonical-document-evals document-state-evals version-store-evals storage-layout-evals storage-runtime-evals style-context-evals language-model-context-evals chat-context-evals chat-search-policy-evals assistant-link-policy-evals style-profile-evals ledger-retention-evals writing-quality-evals gap-fill-evals live-writing-evals-compile live-writing-evals api-key-store-evals openrouter-connection-evals model-availability-evals language-model-wire-evals focus-mode-escape-evals

all: build

# Install exact editor dependencies only when the lockfile changes.
Editor/node_modules/.package-lock.json: Editor/package.json Editor/package-lock.json
	cd Editor && npm ci

# Build TipTap editor bundle
editor: Editor/node_modules/.package-lock.json
	cd Editor && npm run build

typecheck: Editor/node_modules/.package-lock.json
	cd Editor && npm run typecheck

editor-tests: Editor/node_modules/.package-lock.json
	cd Editor && npm test

privacy-check:
	bash scripts/verify-source-privacy.sh

provenance-check:
	bash scripts/verify-app-provenance.sh

# Full deterministic validation used locally and by independent macOS CI.
check: privacy-check provenance-check typecheck evals strict-concurrency-check

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
	swiftc Sources/WordProcessor/Services/ShakespeareRuntime.swift Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/DocumentAssetReference.swift Sources/WordProcessor/Services/PackageFileSafety.swift Sources/WordProcessor/Services/CanonicalDocumentValidator.swift Sources/WordProcessor/Services/DocumentFileStore.swift Sources/WordProcessor/Models/Document.swift scripts/document-state-evals.swift -o /tmp/document-state-evals
	/tmp/document-state-evals

version-store-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareRuntime.swift Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/DocumentAssetReference.swift Sources/WordProcessor/Services/PackageFileSafety.swift Sources/WordProcessor/Services/CanonicalDocumentValidator.swift Sources/WordProcessor/Services/DocumentFileStore.swift Sources/WordProcessor/Services/VersionStore.swift scripts/version-store-evals.swift -lsqlite3 -o /tmp/version-store-evals
	/tmp/version-store-evals

api-key-store-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareRuntime.swift Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/APIKeyStore.swift scripts/api-key-store-evals.swift -o /tmp/api-key-store-evals
	/tmp/api-key-store-evals

storage-layout-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareRuntime.swift Sources/WordProcessor/Services/ShakespeareStorage.swift scripts/storage-layout-evals.swift -o /tmp/storage-layout-evals
	/tmp/storage-layout-evals

storage-runtime-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareRuntime.swift Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/ApplicationStorageStatus.swift scripts/storage-runtime-evals.swift -o /tmp/storage-runtime-evals
	/tmp/storage-runtime-evals

style-context-evals:
	swiftc Sources/WordProcessor/Services/StyleContextAssembler.swift scripts/style-context-evals.swift -o /tmp/style-context-evals
	/tmp/style-context-evals

language-model-context-evals:
	swiftc Sources/WordProcessor/Services/LanguageModelContextBudget.swift scripts/language-model-context-evals.swift -o /tmp/language-model-context-evals
	/tmp/language-model-context-evals

chat-context-evals:
	swiftc Sources/WordProcessor/Services/ChatDocumentContextAssembler.swift scripts/chat-context-evals.swift -o /tmp/chat-context-evals
	/tmp/chat-context-evals

chat-search-policy-evals:
	swiftc Sources/WordProcessor/Services/ChatSearchPolicy.swift scripts/chat-search-policy-evals.swift -o /tmp/chat-search-policy-evals
	/tmp/chat-search-policy-evals

assistant-link-policy-evals:
	swiftc -parse-as-library Sources/WordProcessor/Services/AssistantLinkPolicy.swift scripts/assistant-link-policy-evals.swift -o /tmp/assistant-link-policy-evals
	/tmp/assistant-link-policy-evals

style-profile-evals:
	swiftc Sources/WordProcessor/Services/PackageFileSafety.swift Sources/WordProcessor/Services/StyleProfileCompiler.swift Sources/WordProcessor/Services/StyleProfileDraftStore.swift scripts/style-profile-evals.swift -o /tmp/style-profile-evals
	/tmp/style-profile-evals

ledger-retention-evals:
	swiftc Sources/WordProcessor/Services/PersonalizationLedgerRetention.swift scripts/ledger-retention-evals.swift -o /tmp/ledger-retention-evals
	/tmp/ledger-retention-evals

writing-quality-evals:
	swiftc Sources/WordProcessor/Services/AmbientReviewContract.swift scripts/writing-quality-evals.swift -o /tmp/writing-quality-evals
	/tmp/writing-quality-evals

gap-fill-evals:
	swiftc Sources/WordProcessor/Services/GapFillContract.swift scripts/gap-fill-evals.swift -o /tmp/gap-fill-evals
	/tmp/gap-fill-evals

# Credentialed and cost-capped: four requests, one selected model, 768 output tokens each.
live-writing-evals-compile:
	swiftc -parse-as-library Sources/WordProcessor/Services/AmbientReviewContract.swift Sources/WordProcessor/Services/PackageFileSafety.swift Sources/WordProcessor/Services/StyleProfileCompiler.swift scripts/live-writing-quality-evals.swift -o /tmp/live-writing-quality-evals

live-writing-evals: live-writing-evals-compile
	/tmp/live-writing-quality-evals

openrouter-connection-evals:
	swiftc -parse-as-library Sources/WordProcessor/Services/ShakespeareRuntime.swift Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/InferenceSettings.swift Sources/WordProcessor/Services/OpenRouterConnectionValidator.swift scripts/openrouter-connection-evals.swift -o /tmp/openrouter-connection-evals
	/tmp/openrouter-connection-evals

model-availability-evals:
	swiftc -parse-as-library Sources/WordProcessor/Services/OpenRouterModelAvailabilityService.swift scripts/model-availability-evals.swift -o /tmp/model-availability-evals
	/tmp/model-availability-evals

language-model-wire-evals:
	swiftc Sources/WordProcessor/Services/ShakespeareRuntime.swift Sources/WordProcessor/Services/ShakespeareStorage.swift Sources/WordProcessor/Services/APIKeyStore.swift Sources/WordProcessor/Services/InferenceSettings.swift Sources/WordProcessor/Services/LanguageModelUsageStore.swift Sources/WordProcessor/Services/LanguageModelService.swift scripts/language-model-wire-evals.swift -o /tmp/language-model-wire-evals
	/tmp/language-model-wire-evals

focus-mode-escape-evals:
	swiftc -parse-as-library Sources/WordProcessor/Views/FocusModeEscapeMonitor.swift scripts/focus-mode-escape-evals.swift -o /tmp/focus-mode-escape-evals
	/tmp/focus-mode-escape-evals

evals: editor-tests document-asset-evals document-package-safety-evals canonical-document-evals document-state-evals version-store-evals storage-layout-evals storage-runtime-evals style-context-evals language-model-context-evals chat-context-evals chat-search-policy-evals assistant-link-policy-evals style-profile-evals ledger-retention-evals writing-quality-evals gap-fill-evals live-writing-evals-compile api-key-store-evals openrouter-connection-evals model-availability-evals language-model-wire-evals focus-mode-escape-evals

# Build release
build: copy-assets
	swift build -c release

strict-concurrency-check: copy-assets
	swift build -c release -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors

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
