# image-build-dns-nodecache

This repo builds hardened, statically-linked Go binaries from the
[kubernetes-sigs/node-local-dns](https://github.com/kubernetes-sigs/node-local-dns) repo, which is published upstream at `registry.k8s.io/dns/k8s-dns-node-cache`

## Version tracking

`COMMIT` pins the exact upstream `master` commit used for the build. `VERSION`
contains the downstream image and release version in `<upstream-tag>-rN` form.

UpdateCLI resolves the nearest upstream semantic-version tag reachable from the
new commit. A commit update under the same upstream tag increments `rN`; a new
upstream tag resets the revision to `r1`.