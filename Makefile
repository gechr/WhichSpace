BUILD_CONFIGURATION      ?= Debug
MACOSX_DEPLOYMENT_TARGET ?= 14.0

ifdef WHICHSPACE_CODE_SIGN_IDENTITY
SIGNING_FLAGS := WHICHSPACE_CODE_SIGN_IDENTITY='$(WHICHSPACE_CODE_SIGN_IDENTITY)'
endif

ifdef RELEASE
BUILD_CONFIGURATION := Release
endif

# Dedicated DerivedData so rebuilding via `make build`/`make test` never
# rewrites the bundle the running app was launched from
RUN_DERIVED_DATA := build/run
RUN_APP          := $(RUN_DERIVED_DATA)/Build/Products/Debug/WhichSpace.app

# Dev version stamp from git describe, e.g. 1.2.0-18-g6d9e2c7-dirty
RUN_VERSION ?= $(patsubst v%,%,$(shell git describe --tags --dirty 2>/dev/null || echo v0.0.0-dev))

.PHONY: all
all: clean fmt lint test

.PHONY: build
build:
	@xcodebuild build \
		-project WhichSpace.xcodeproj \
		-scheme WhichSpace \
		-configuration $(BUILD_CONFIGURATION) \
		-destination 'platform=macOS' \
		$(SIGNING_FLAGS) \
		MACOSX_DEPLOYMENT_TARGET=$(MACOSX_DEPLOYMENT_TARGET)

.PHONY: clean
clean:
	@xcodebuild clean \
		-project WhichSpace.xcodeproj \
		-scheme WhichSpace \
		-configuration $(BUILD_CONFIGURATION) \
		-destination 'platform=macOS'

.PHONY: check
check:
	@swiftformat --lint .

.PHONY: fix
fix: fmt
	@swiftlint --fix .

.PHONY: fmt
fmt:
	@clover format
	@rumdl fmt --quiet
	@swiftformat .

.PHONY: lint
lint:
	@swiftlint lint --strict
	@xmllint --noout --nonet --valid WhichSpace/WhichSpace.sdef

.PHONY: run
run:
	@pkill -x WhichSpace || :
	@rm -rf $(RUN_APP)
	@xcodebuild -scheme WhichSpace -configuration Debug -derivedDataPath $(RUN_DERIVED_DATA) build $(SIGNING_FLAGS) MARKETING_VERSION=$(RUN_VERSION)
	@open $(RUN_APP) $(if $(LANGUAGE),--args -AppleLanguages "($(LANGUAGE))")

.PHONY: test
test:
	@xcodebuild test \
		-project WhichSpace.xcodeproj \
		-scheme WhichSpace \
		-destination 'platform=macOS' \
		$(SIGNING_FLAGS) \
		MACOSX_DEPLOYMENT_TARGET=$(MACOSX_DEPLOYMENT_TARGET)

.PHONY: update
update:
	@clover run
	@swift package update
