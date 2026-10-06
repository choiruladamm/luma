APP := apps/mobile
FLUTTER := cd $(APP) && fvm flutter
DART := cd $(APP) && fvm dart

.PHONY: help get gen watch run release profile test analyze format check clean

help: ## list commands
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-8s %s\n", $$1, $$2}'

get: ## pub get
	$(FLUTTER) pub get

gen: ## codegen: drift, riverpod, freezed (build_runner)
	$(DART) run build_runner build

watch: ## codegen in watch mode
	$(DART) run build_runner watch

run: ## run app in debug (device: d=<id>)
	$(FLUTTER) run $(if $(d),-d $(d))

release: ## install release build on iPhone, redo every 7 days, data kept (d=<id>)
	$(FLUTTER) run --release $(if $(d),-d $(d))

profile: ## run app in profile mode, real perf (d=<id>)
	$(FLUTTER) run --profile $(if $(d),-d $(d))

test: ## run tests, 30s cap per test so a hang fails fast (one file/folder: make test t=test/domain)
	$(FLUTTER) test --timeout 30s $(t)

analyze: ## static analysis
	$(FLUTTER) analyze

format: ## dart format lib + test
	$(DART) format lib $(if $(wildcard $(APP)/test),test)

check: format analyze test ## format, analyze, test

clean: ## flutter clean + pub get
	$(FLUTTER) clean && fvm flutter pub get
