APP := apps/mobile
FLUTTER := cd $(APP) && fvm flutter
DART := cd $(APP) && fvm dart

.PHONY: help get gen brand live chat-spike chat-spike-live chat-oracle-live chat-discussion-live chat-adaptive-live chat-retrieval chat-dense-live chat-dense-replay chat-heldout-live chat-refine-live chat-validation2-live chat-recovery-live chat-validation3-live watch run release dev run-android release-android dev-android apk profile test analyze format check clean

help: ## list commands
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

get: ## pub get
	$(FLUTTER) pub get

gen: ## codegen: drift, riverpod, freezed (build_runner)
	$(DART) run build_runner build

brand: ## re-render app icon, launch logo, wordmark from assets/brand/*.svg (Chrome + ImageMagick)
	cd $(APP) && sh tool/brand.sh

watch: ## codegen in watch mode
	$(DART) run build_runner watch

run: ## run Luma in debug (device: d=<id>; f=dev for Luma Dev)
	$(FLUTTER) run $(if $(f),--flavor $(f)) $(if $(d),-d $(d))

release: ## install release build on iPhone, redo every 7 days, data kept (d=<id>), master only
	@test "$$(git rev-parse --abbrev-ref HEAD)" = master || { echo "make release cuma dari master (app Luma, data asli). Fitur: Luma Dev"; exit 1; }
	$(FLUTTER) run --release $(if $(d),-d $(d))

dev: ## install release build of Luma Dev (own data & Keychain), any branch (d=<id>)
	$(FLUTTER) run --release --flavor dev $(if $(d),-d $(d))

run-android: ## run Luma on Android in debug (device: d=<id>; f=dev for Luma Dev, default prod)
	$(FLUTTER) run --flavor $(or $(f),prod) $(if $(d),-d $(d))

release-android: ## install release build of Luma on Android, signed with the fixed keystore (d=<id>), master only
	@test "$$(git rev-parse --abbrev-ref HEAD)" = master || { echo "make release-android cuma dari master (app Luma, data asli). Fitur: make dev-android"; exit 1; }
	$(FLUTTER) run --release --flavor prod $(if $(d),-d $(d))

dev-android: ## install release build of Luma Dev on Android (own data & Keystore), any branch (d=<id>)
	$(FLUTTER) run --release --flavor dev $(if $(d),-d $(d))

apk: ## build release APK of Luma (prod) for sideload, master only
	@test "$$(git rev-parse --abbrev-ref HEAD)" = master || { echo "make apk cuma dari master (app Luma, data asli)"; exit 1; }
	$(FLUTTER) build apk --release --flavor prod
	@echo "APK: $(APP)/build/app/outputs/flutter-apk/app-prod-release.apk"

profile: ## run app in profile mode, real perf (d=<id>)
	$(FLUTTER) run --profile $(if $(d),-d $(d))

test: ## run tests, 30s cap per test so a hang fails fast (one file/folder: make test t=test/domain)
	$(FLUTTER) test --timeout 30s $(t)

live: ## real OpenRouter call, key from .env (gitignored; m=<model id> optional)
	@set -a; . ./.env; set +a; cd $(APP) && OPENROUTER_MODEL=$(m) fvm flutter test test/data/openrouter_live_test.dart

chat-spike: ## #113 offline corpus + isolation/budget/citation checks (no API)
	$(FLUTTER) test --timeout 30s test/data/book_chat_spike_test.dart

chat-retrieval: ## #113 offline development chunk/query replay (no API, no held-out)
	$(FLUTTER) test --timeout 30s test/data/book_chat_retrieval_test.dart

chat-dense-live: ## #113 paid development embedding indexing; BOOK_CHAT_EMBEDDING_MODEL optional
	@set -a; . ./.env; set +a; cd $(APP) && BOOK_CHAT_EMBEDDING_RUN=1 BOOK_CHAT_EMBEDDING_LIVE=1 fvm flutter test test/data/book_chat_dense_eval_test.dart

chat-dense-replay: ## #113 offline replay; fails if embedding cache is incomplete
	cd $(APP) && BOOK_CHAT_EMBEDDING_RUN=1 BOOK_CHAT_EMBEDDING_LIVE=0 fvm flutter test test/data/book_chat_dense_eval_test.dart

chat-heldout-live: ## #113 final FROZEN held-out: consumes split, 80 fresh answers, no tuning
	@set -a; . ./.env; set +a; cd $(APP) && BOOK_CHAT_HELDOUT_LIVE=1 fvm flutter test test/data/book_chat_heldout_live_test.dart

chat-refine-live: ## #113 paid development/consumed diagnostics; cached embeddings only
	@set -a; . ./.env; set +a; cd $(APP) && BOOK_CHAT_REFINEMENT_LIVE=1 fvm flutter test test/data/book_chat_refinement_live_test.dart

chat-validation2-live: ## #113 fresh book-level validation2; frozen pipeline, consumes split
	@set -a; . ./.env; set +a; cd $(APP) && BOOK_CHAT_VALIDATION2_LIVE=1 fvm flutter test test/data/book_chat_validation2_live_test.dart

chat-recovery-live: ## #113 paid diagnostic on consumed validation2; no independent validation claim
	@set -a; . ./.env; set +a; cd $(APP) && BOOK_CHAT_RECOVERY_LIVE=1 fvm flutter test test/data/book_chat_recovery_live_test.dart

chat-validation3-live: ## #113 fresh book-level validation3; frozen pipeline, consumes split
	@set -a; . ./.env; set +a; cd $(APP) && BOOK_CHAT_VALIDATION3_LIVE=1 fvm flutter test test/data/book_chat_validation3_live_test.dart

chat-spike-live: ## #113 paid corpus, local .env; m=<model>, BOOK_CHAT_CASE=E01 optional
	@set -a; . ./.env; set +a; cd $(APP) && BOOK_CHAT_LIVE=1 OPENROUTER_MODEL=$(m) fvm flutter test test/data/book_chat_live_test.dart

chat-oracle-live: ## #113 paid DEVELOPMENT oracle A/B; held-out is never queried
	@set -a; . ./.env; set +a; cd $(APP) && BOOK_CHAT_ORACLE_LIVE=1 OPENROUTER_MODEL=$(m) fvm flutter test test/data/book_chat_oracle_live_test.dart

chat-adaptive-live: ## #138 paid global scan + continuation; GLM primary, m=qwen/qwen3.8-flash fallback
	@set -a; . ./.env; set +a; cd $(APP) && BOOK_CHAT_ADAPTIVE_LIVE=1 OPENROUTER_MODEL=$(or $(m),z-ai/glm-5.3-flash) fvm flutter test --timeout 30s test/data/book_chat_adaptive_live_test.dart

chat-discussion-live: ## #136 bounded paid DEVELOPMENT answer pilot, two cases; m=<model> optional
	@set -a; . ./.env; set +a; cd $(APP) && BOOK_CHAT_DISCUSSION_LIVE=1 OPENROUTER_MODEL=$(or $(m),z-ai/glm-5.3-flash) fvm flutter test --timeout 30s test/data/book_chat_discussion_live_test.dart

analyze: ## static analysis
	$(FLUTTER) analyze

format: ## dart format lib + test
	$(DART) format lib $(if $(wildcard $(APP)/test),test)

check: format analyze test ## format, analyze, test

clean: ## flutter clean + pub get
	$(FLUTTER) clean && fvm flutter pub get
