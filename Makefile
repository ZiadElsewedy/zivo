# ZIVO run/build configurations. See docs/build_configurations.md.
# Three configs = three Flutter build modes, each with its own dart-defines.

DEV_DEFINES     = --dart-define-from-file=config/development.json
PROFILE_DEFINES = --dart-define-from-file=config/profile.json
RELEASE_DEFINES = --dart-define-from-file=config/release.json

.DEFAULT_GOAL := help

.PHONY: help dev profile release build-apk build-ipa build-apk-profile gates hooks

help: ## List the available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

dev: ## Run Development (debug) on the default device
	flutter run $(DEV_DEFINES)

profile: ## Run Profile — the M7 config — on a PHYSICAL device
	flutter run --profile $(PROFILE_DEFINES)

release: ## Run Release on the default device
	flutter run --release $(RELEASE_DEFINES)

build-apk: ## Build the Release Android APK
	flutter build apk --release $(RELEASE_DEFINES)

build-apk-profile: ## Build a Profile Android APK (M7)
	flutter build apk --profile $(PROFILE_DEFINES)

build-ipa: ## Build the Release iOS archive
	flutter build ipa --release $(RELEASE_DEFINES)

gates: ## Run the local quality gates (analyze + test)
	flutter analyze && flutter test

hooks: ## Install shared git hooks (docs/STATE.md freshness check)
	@chmod +x scripts/hooks/* 2>/dev/null || true
	@git config core.hooksPath scripts/hooks
	@echo "Git hooks installed (core.hooksPath = scripts/hooks). Run once per clone."
