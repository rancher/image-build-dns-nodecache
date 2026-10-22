ARG BCI_IMAGE=registry.suse.com/bci/bci-busybox
ARG GO_IMAGE=rancher/hardened-build-base:v1.26.10b1

# Image that provides cross compilation tooling.
FROM --platform=$BUILDPLATFORM rancher/mirrored-tonistiigi-xx:1.6.1 AS xx

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS base
COPY --from=xx / /
RUN set -x && \
    apk add file make git clang lld

FROM base AS builder
ARG TARGETPLATFORM
RUN set -x && \
    xx-apk add musl-dev gcc  lld 
ARG COMMIT
ARG VERSION
ARG K3S_ROOT_VERSION=v0.15.4
RUN export ARCH=$(xx-info arch) &&\
    case "${ARCH}" in \
        amd64)  XTABLES_SHA256="430d9716c4977e549356d02c24fa79fb7697e3cdecbafe78735de16ed595b81b" ;; \
        arm64)  XTABLES_SHA256="26ccf8b7c2678410965bcf85a10be297b757bf3aa75f022350b87ca6ed363695" ;; \
        arm)    XTABLES_SHA256="e7a8fb7edecce854520ab8c50e71fd72d806d9b5853ebdd6065dc67d9bcaad9b" ;; \
        *)      echo "No pinned SHA256 for k3s-root-xtables on arch: ${ARCH}" >&2; exit 1 ;; \
    esac &&\
    mkdir -p /opt/xtables/ &&\
    wget -q "https://github.com/rancher/k3s-root/releases/download/${K3S_ROOT_VERSION}/k3s-root-xtables-${ARCH}.tar" -O /opt/xtables/k3s-root-xtables.tar &&\
    echo "${XTABLES_SHA256}  /opt/xtables/k3s-root-xtables.tar" | sha256sum -c -
RUN tar xvf /opt/xtables/k3s-root-xtables.tar -C /opt/xtables

ARG PKG=github.com/kubernetes-sigs/node-local-dns
RUN git clone --depth=1 https://${PKG}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --depth=1 origin ${COMMIT} && \
    git checkout ${COMMIT}
COPY go-mod-overrides ./go-mod-overrides
RUN go-mod-replacer -local ./go-mod-overrides
RUN xx-go --wrap &&\
    GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.VERSION=${VERSION}" \
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

FROM ${BCI_IMAGE}
ARG COMMIT
ARG VERSION
LABEL org.opencontainers.image.revision=${COMMIT} \
    org.opencontainers.image.version=${VERSION}
COPY --from=strip_binary /node-cache /node-cache
COPY --from=builder /opt/xtables/bin/ /usr/sbin/
ENTRYPOINT ["/node-cache"]
