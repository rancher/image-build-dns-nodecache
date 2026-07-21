ARG BCI_IMAGE=registry.suse.com/bci/bci-nano:16.0
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

ARG SRC=github.com/kubernetes-sigs/node-local-dns
ARG PKG=github.com/kubernetes-sigs/node-local-dns
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git tag --list
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
COPY go-mod-overrides ./go-mod-overrides
RUN go-mod-overrides.sh ./go-mod-overrides
RUN xx-go --wrap &&\
    GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.VERSION=${TAG}" \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o . ./...
RUN go-assert-static.sh node-cache
RUN if [ `xx-info arch` = "amd64" ]; then \
        go-assert-boring.sh node-cache; \
    fi
RUN install  node-cache /usr/local/bin

FROM ${GO_IMAGE} AS k3s-root
ARG TARGETARCH
ARG K3S_ROOT_VERSION=v0.15.2
RUN case "${TARGETARCH}" in \
        amd64)  K3S_ROOT_SHA256="9e56393cf828583b50b6b0e66cc47cb6a5e1d0489eab1436421bc20c56c0cf65" ;; \
        arm64)  K3S_ROOT_SHA256="7a754f4aeb1771b2b147ac8ff48fbc0a152f4ab1c6b4f16f94b1121e5eaaba50" ;; \
        arm)    K3S_ROOT_SHA256="af8614e5b9e2f87d30bd4387c512703c6bf2bc53a3764e5181ef2f2eaccab8d2" ;; \
        *)      echo "No pinned SHA256 for k3s-root on arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    mkdir -p /opt/k3s-root && \
    wget -q "https://github.com/rancher/k3s-root/releases/download/${K3S_ROOT_VERSION}/k3s-root-${TARGETARCH}.tar" -O /opt/k3s-root/k3s-root.tar && \
    echo "${K3S_ROOT_SHA256}  /opt/k3s-root/k3s-root.tar" | sha256sum -c -
RUN tar xvf /opt/k3s-root/k3s-root.tar -C /opt/k3s-root && \
    mkdir -p /opt/k3s-root/usr && \
    mv /opt/k3s-root/bin/aux /opt/k3s-root/usr/sbin && \
    ln -sf ../bin/busybox /opt/k3s-root/usr/sbin/modprobe && \
    ln -sf ../bin/busybox /opt/k3s-root/usr/sbin/mount

#strip needs to run on TARGETPLATFORM, not BUILDPLATFORM
FROM ${GO_IMAGE} AS strip_binary
COPY --from=builder /usr/local/bin/node-cache /node-cache
RUN strip /node-cache

FROM bci
COPY --from=strip_binary /node-cache /node-cache
COPY --from=k3s-root /opt/k3s-root/usr/sbin /usr/sbin/
COPY --from=k3s-root /opt/k3s-root/bin /bin/
ENTRYPOINT ["/node-cache"]
