SEVERITIES = HIGH,CRITICAL

UNAME_M = $(shell uname -m)
ifndef TARGET_PLATFORMS
	ifeq ($(UNAME_M), x86_64)
		TARGET_PLATFORMS:=linux/amd64
	else ifeq ($(UNAME_M), aarch64)
		TARGET_PLATFORMS:=linux/arm64
	else 
		TARGET_PLATFORMS:=linux/$(UNAME_M)
	endif
endif

TRACKED_VERSION := $(shell cat VERSION)
COMMIT ?= $(shell cat COMMIT)
VERSION ?= ${GITHUB_ACTION_TAG}

ifeq ($(VERSION),)
VERSION := $(TRACKED_VERSION)
endif

ifneq ($(GITHUB_ACTION_TAG),)
ifneq ($(GITHUB_ACTION_TAG),$(TRACKED_VERSION))
$(error GitHub release tag $(GITHUB_ACTION_TAG) does not match VERSION $(TRACKED_VERSION))
endif
endif

REPO ?= rancher
IMAGE = $(REPO)/hardened-dns-node-cache:$(VERSION)
BUILD_OPTS = \
	--platform=$(TARGET_PLATFORMS) \
	--build-arg COMMIT=$(COMMIT) \
	--build-arg VERSION=$(VERSION) \
	--tag "$(IMAGE)"

.PHONY: image-build
image-build:
	docker buildx build \
		$(BUILD_OPTS) \
		--pull \
		--load \
	.

.PHONY: push-image
push-image:
	docker buildx build \
		$(BUILD_OPTS) \
		$(IID_FILE_FLAG) \
		$(BUILDX_ARGS) \
		--push \
		.

.PHONY: push-prime-image
push-prime-image:
	BUILDX_ARGS="--sbom=true --attest type=provenance,mode=max" \
	$(MAKE) push-image

.PHONY: image-scan
image-scan:
	trivy image --severity $(SEVERITIES) --no-progress --ignore-unfixed $(IMAGE)

.PHONY: log
log:
	@echo "COMMIT=$(COMMIT)"
	@echo "VERSION=$(VERSION)"
	@echo "REPO=$(REPO)"
	@echo "IMAGE=$(IMAGE)"
	@echo "UNAME_M=$(UNAME_M)"
	@echo "TARGET_PLATFORMS=$(TARGET_PLATFORMS)"
