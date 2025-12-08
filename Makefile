MACOSX_DEPLOYMENT_TARGET ?= 14.0

.PHONY: build
build:
	@xcodebuild build \
		-project WhichSpace.xcodeproj \
		-scheme WhichSpace \
		-destination 'platform=macOS' \
		MACOSX_DEPLOYMENT_TARGET=$(MACOSX_DEPLOYMENT_TARGET)

.PHONY: check
check:
	@swiftformat --lint .

.PHONY: fix
fix: fmt
	@swiftlint --fix .

.PHONY: fmt
fmt:
	@swiftformat .

.PHONY: lint
lint:
	@swiftlint lint --strict

.PHONY: run
run:
	@pkill -x WhichSpace || :
	@rm -rf ~/Library/Developer/Xcode/DerivedData/WhichSpace-*/Build/Products/Debug/WhichSpace.app
	@xcodebuild -scheme WhichSpace -configuration Debug build
	@open ~/Library/Developer/Xcode/DerivedData/WhichSpace-*/Build/Products/Debug/WhichSpace.app

.PHONY: test
test:
	@xcodebuild test \
		-project WhichSpace.xcodeproj \
		-scheme WhichSpace \
		-destination 'platform=macOS' \
		MACOSX_DEPLOYMENT_TARGET=$(MACOSX_DEPLOYMENT_TARGET)

.PHONY: update
update:
	@swift package update
