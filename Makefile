APP := apps/mobile
FLUTTER := cd $(APP) && fvm flutter
DART := cd $(APP) && fvm dart

.PHONY: help get gen brand live watch run release profile test analyze format check clean

help: ## list commands
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-8s %s\n", $$1, $$2}'

get: ## pub get
	$(FLUTTER) pub get

gen: ## codegen: drift, riverpod, freezed (build_runner)
	$(DART) run build_runner build

brand: ## re-render app icon, launch logo, wordmark from assets/brand/*.svg (Chrome + ImageMagick)
	cd $(APP) && sh tool/brand.sh

watch: ## codegen in watch mode
	$(DART) run build_runner watch

run: ## run app in debug (device: d=<id>)
	$(FLUTTER) run $(if $(d),-d $(d))

release: ## install release build on iPhone, redo every 7 days, data kept (d=<id>), master only
	@test "$$(git rev-parse --abbrev-ref HEAD)" = master || { echo "make release cuma dari master (app Luma, data asli). Fitur: Luma Dev"; exit 1; }
	$(FLUTTER) run --release $(if $(d),-d $(d))

profile: ## run app in profile mode, real perf (d=<id>)
	$(FLUTTER) run --profile $(if $(d),-d $(d))

test: ## run tests, 30s cap per test so a hang fails fast (one file/folder: make test t=test/domain)
	$(FLUTTER) test --timeout 30s $(t)

live: ## real OpenRouter call, key from .env (gitignored; m=<model id> optional)
	@set -a; . ./.env; set +a; cd $(APP) && OPENROUTER_MODEL=$(m) fvm flutter test test/data/openrouter_live_test.dart

analyze: ## static analysis
	$(FLUTTER) analyze

format: ## dart format lib + test
	$(DART) format lib $(if $(wildcard $(APP)/test),test)

check: format analyze test ## format, analyze, test

clean: ## flutter clean + pub get
	$(FLUTTER) clean && fvm flutter pub get
