ARG BCI_IMAGE=registry.suse.com/bci/bci-busybox
ARG GO_IMAGE=rancher/hardened-build-base:v1.22.10b1

# Image that provides cross compilation tooling.
FROM --platform=$BUILDPLATFORM rancher/mirrored-tonistiigi-xx:1.5.0 as xx

FROM ${BCI_IMAGE} as bci

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} as base
COPY --from=xx / /
RUN set -x && \
    apk add file make git clang lld

FROM base as builder
ARG TARGETPLATFORM
RUN set -x && \
    xx-apk add musl-dev gcc  lld 
ARG TAG=1.24.0
ARG K3S_ROOT_VERSION=v0.14.1
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
RUN xx-go --wrap &&\
    GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.VERSION=${TAG}" \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o . ./...
RUN go-assert-static.sh node-cache
RUN if [ `xx-info arch` = "amd64" ]; then \
        go-assert-boring.sh node-cache; \
    fi
RUN install  node-cache /usr/local/bin

#strip needs to run on TARGETPLATFORM, not BUILDPLATFORM
FROM ${GO_IMAGE} as strip_binary
COPY --from=builder /usr/local/bin/node-cache /node-cache
RUN strip /node-cache

FROM bci
COPY --from=strip_binary /node-cache /node-cache
COPY --from=builder /opt/xtables/bin/ /usr/sbin/
ENTRYPOINT ["/node-cache"]
