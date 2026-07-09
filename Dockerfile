ARG BCI_IMAGE=registry.suse.com/bci/bci-busybox
ARG GO_IMAGE=rancher/hardened-build-base:v1.25.12b1

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
ARG TAG=1.26.8
ARG K3S_ROOT_VERSION=v0.15.2
RUN export ARCH=$(xx-info arch) &&\
    case "${ARCH}" in \
        amd64)  XTABLES_SHA256="1272950a6dd969ced16f36eed91f3cc3feb552edbb7d6dcfbfc9b04930d9ba3f" ;; \
        arm64)  XTABLES_SHA256="9f1d32c3c3ffbc8b4da2df06e931fa526651bea166a77f81e4ab3b86358d837f" ;; \
        arm)    XTABLES_SHA256="e6ae1a422f3d2d85347439ecd66eec5d5a05b0ce960f5a7d888610240cb14067" ;; \
        *)      echo "No pinned SHA256 for k3s-root-xtables on arch: ${ARCH}" >&2; exit 1 ;; \
    esac &&\
    mkdir -p /opt/xtables/ &&\
    wget -q "https://github.com/rancher/k3s-root/releases/download/${K3S_ROOT_VERSION}/k3s-root-xtables-${ARCH}.tar" -O /opt/xtables/k3s-root-xtables.tar &&\
    echo "${XTABLES_SHA256}  /opt/xtables/k3s-root-xtables.tar" | sha256sum -c -
RUN tar xvf /opt/xtables/k3s-root-xtables.tar -C /opt/xtables

ARG SRC=github.com/kubernetes/dns
ARG PKG=github.com/kubernetes/dns
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git tag --list
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN go mod edit -replace github.com/coredns/coredns=github.com/coredns/coredns@v1.14.3 && \
    go mod edit -replace google.golang.org/grpc=google.golang.org/grpc@v1.79.3 && \
    go mod edit -replace go.opentelemetry.io/otel/sdk=go.opentelemetry.io/otel/sdk@v1.43.0 && \
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
