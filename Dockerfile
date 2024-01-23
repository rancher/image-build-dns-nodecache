ARG BCI_IMAGE=registry.suse.com/bci/bci-busybox
ARG GO_IMAGE=rancher/hardened-build-base:v1.20.7b3
# We need iptables and ip6tables. We will get them from the hardened kubernetes image
ARG KUBERNETES=rancher/hardened-kubernetes:v1.27.2-rke2r1-build20230518

ARG TAG="1.22.20"
ARG ARCH="amd64"
FROM ${BCI_IMAGE} as bci
FROM ${KUBERNETES} as kubernetes
FROM ${GO_IMAGE} as base

RUN set -x && \
    apk --no-cache add \
    file \
    gcc \
    git \
    make

FROM base as builder
ARG SRC=github.com/kubernetes/dns
ARG PKG=github.com/kubernetes/dns
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
ARG TAG
ARG ARCH
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
COPY --from=kubernetes /usr/sbin/ip* /usr/sbin/
COPY --from=kubernetes /usr/sbin/xtables* /usr/sbin/
ENTRYPOINT ["/node-cache"]
