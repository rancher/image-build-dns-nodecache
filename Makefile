SEVERITIES = HIGH,CRITICAL

ifeq ($(ARCH),)
ARCH=$(shell go env GOARCH)
endif

BUILD_META=-build$(shell date +%Y%m%d)
ORG ?= rancher
PKG ?= github.com/kubernetes/dns
SRC ?= github.com/kubernetes/dns
TAG ?= 1.21.1$(BUILD_META)

ifneq ($(DRONE_TAG),)
TAG := $(DRONE_TAG)
endif

ifeq (,$(filter %$(BUILD_META),$(TAG)))
$(error TAG needs to end with build metadata: $(BUILD_META))
endif

.PHONY: image-build
image-build:
	docker build \
		--pull \
		--build-arg PKG=$(PKG) \
		--build-arg SRC=$(SRC) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--tag $(ORG)/hardened-dns-node-cache:$(TAG) \
		--tag $(ORG)/hardened-dns-node-cache:$(TAG)-$(ARCH) \
	.

.PHONY: image-push
image-push:
	docker push $(ORG)/hardened-dns-node-cache:$(TAG)-$(ARCH)

.PHONY: image-manifest
image-manifest:
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create --amend \
		$(ORG)/hardened-dns-node-cache:$(TAG) \
		$(ORG)/hardened-dns-node-cache:$(TAG)-$(ARCH)
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest push \
		$(ORG)/hardened-dns-node-cache:$(TAG)

.PHONY: image-scan
image-scan:
	trivy --severity $(SEVERITIESdnsNodeCache) --no-progress --ignore-unfixed $(ORG)/hardened-dns-node-cache:$(TAG)

