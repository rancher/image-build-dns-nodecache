ARG BCI_IMAGE=registry.suse.com/bci/bci-busybox
ARG GO_IMAGE=rancher/hardened-build-base:v1.23.12b1

# Image that provides cross compilation tooling.
FROM --platform=$BUILDPLATFORM rancher/mirrored-tonistiigi-xx:1.6.1 AS xx

FROM ${BCI_IMAGE} AS bci

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS base
COPY --from=xx / /
RUN set -x && \
    apk add file make git clang lld

FROM base AS builder
ARG TARGETPLATFORM
RUN set -x && \
    xx-apk add musl-dev gcc  lld 
ARG TAG=1.26.5
ARG K3S_ROOT_VERSION=v0.15.0
RUN export ARCH=$(xx-info arch) &&\
    mkdir -p /opt/xtables/ &&\
    wget https://github.com/rancher/k3s-root/releases/download/${K3S_ROOT_VERSION}/k3s-root-xtables-${ARCH}.tar -O /opt/xtables/k3s-root-xtables.tar
RUN tar xvf /opt/xtables/k3s-root-xtables.tar -C /opt/xtables

ARG SRC=github.com/kubernetes/dns
ARG PKG=github.com/kubernetes/dns
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git tag --list
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
# Temporary patch for CVE-2025-47950
# Remove once kubernetes/dns is updated to a version that includes the fix.
# Also includes fix for https://github.com/kubernetes-sigs/structured-merge-diff/issues/268
RUN go mod edit -replace github.com/coredns/coredns=github.com/coredns/coredns@v1.12.2; \
    go mod edit -replace sigs.k8s.io/structured-merge-diff/v4=sigs.k8s.io/structured-merge-diff/v4@v4.4.3; \
    go mod tidy && go mod vendor
RUN xx-go --wrap &&\
    GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.VERSION=${TAG}" \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o . ./...
RUN go-assert-static.sh node-cache
RUN if [ `xx-info arch` = "amd64" ]; then \
        go-assert-boring.sh node-cache; \
    fi
RUN install  node-cache /usr/local/bin

#strip needs to run on TARGETPLATFORM, not BUILDPLATFORM
FROM ${GO_IMAGE} AS strip_binary
COPY --from=builder /usr/local/bin/node-cache /node-cache
RUN strip /node-cache

FROM bci
COPY --from=strip_binary /node-cache /node-cache
COPY --from=builder /opt/xtables/bin/ /usr/sbin/
ENTRYPOINT ["/node-cache"]
