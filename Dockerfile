ARG BCI_IMAGE=registry.suse.com/bci/bci-nano:16.0
ARG GO_IMAGE=rancher/hardened-build-base:v1.25.11b1

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
ARG K3S_ROOT_VERSION=v0.15.0
RUN export ARCH=$(xx-info arch) &&\
    case "${ARCH}" in \
        amd64)  K3S_ROOT_SHA256="20066815d9941185fce3934cc3bae2fa3e2dbb46ca7e63462efb2ea59f1b15c4" ;; \
        arm64)  K3S_ROOT_SHA256="4bdfc715dc8b5e2c4956f8686b895a56386f4cc6468215dcd22130a680650577" ;; \
        arm)    K3S_ROOT_SHA256="2e43dac7750da52a756a9d4e8598d6e89937d565582660b26ca124bd9c8dbfaa" ;; \
        *)      echo "No pinned SHA256 for k3s-root on arch: ${ARCH}" >&2; exit 1 ;; \
    esac &&\
    mkdir -p /opt/k3s-root/ &&\
    wget -q "https://github.com/rancher/k3s-root/releases/download/${K3S_ROOT_VERSION}/k3s-root-${ARCH}.tar" -O /opt/k3s-root/k3s-root.tar &&\
    echo "${K3S_ROOT_SHA256}  /opt/k3s-root/k3s-root.tar" | sha256sum -c -
# Extract the k3s-root rootfs. It provides a statically linked busybox and
# coreutils (needed by the iptables wrapper scripts since bci-nano ships no
# shell) plus the static iptables/xtables binaries under bin/aux. Move the
# xtables binaries into usr/sbin so bin/ contains only the shell utilities.
RUN tar xf /opt/k3s-root/k3s-root.tar -C /opt/k3s-root &&\
    mkdir -p /opt/k3s-root/usr/sbin &&\
    mv /opt/k3s-root/bin/aux/* /opt/k3s-root/usr/sbin/ &&\
    rmdir /opt/k3s-root/bin/aux

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
COPY --from=builder /opt/k3s-root/bin/ /bin/
COPY --from=builder /opt/k3s-root/usr/sbin/ /usr/sbin/
ENTRYPOINT ["/node-cache"]
