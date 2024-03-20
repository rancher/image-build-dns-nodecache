ARG BCI_IMAGE=registry.suse.com/bci/bci-busybox
ARG GO_IMAGE=rancher/hardened-build-base:v1.20.14b1

FROM --platform=$BUILDPLATFORM ${BCI_IMAGE} as bci
FROM --platform=$BUILDPLATFORM ${GO_IMAGE} as base

RUN set -x && \
    apk --no-cache add \
    file \
    gcc \
    git \
    make

FROM base as builder
ARG K3S_ROOT_VERSION=v0.13.0
ARG TAG=1.23.0
ARG ARCH
ADD https://github.com/rancher/k3s-root/releases/download/${K3S_ROOT_VERSION}/k3s-root-xtables-${ARCH}.tar /opt/xtables/k3s-root-xtables.tar
RUN tar xvf /opt/xtables/k3s-root-xtables.tar -C /opt/xtables
ARG SRC=github.com/kubernetes/dns
ARG PKG=github.com/kubernetes/dns
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git tag --list
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN GOARCH=${ARCH} GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.VERSION=${TAG}" \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o . ./...
RUN go-assert-static.sh node-cache
RUN if [ "${ARCH}" = "amd64" ]; then \
        go-assert-boring.sh node-cache; \
    fi
RUN install -s node-cache /usr/local/bin

FROM bci
COPY --from=builder /usr/local/bin/node-cache /node-cache
COPY --from=builder /opt/xtables/bin/ /usr/sbin/
ENTRYPOINT ["/node-cache"]
