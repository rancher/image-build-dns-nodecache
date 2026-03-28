ARG BCI_IMAGE=registry.suse.com/bci/bci-busybox
ARG GO_IMAGE=rancher/hardened-build-base:v1.25.8b1

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
        amd64)  XTABLES_SHA256="8dc4673efcbc4caf0f9a5a20b4df13609a9f305b8b42e5df842c9808ade3402d" ;; \
        arm64)  XTABLES_SHA256="7d85b0102e5a340a038c577fbbdc7fd84c018da31595a84453fa564b99e2c0fd" ;; \
        arm)    XTABLES_SHA256="41779cf870fdcc21dcc459be0e500b32ae55fc8c2c8587cd08dee7aa19d47673" ;; \
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
