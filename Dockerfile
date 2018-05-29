# Usage:
#
# Build the container
# $ docker build . -t siddhu/hackage-server
#
# Shell into the container
# $ docker run -it -p 8080:8080 siddhu/hackage-server /bin/bash
#
# Run the server
# Docker> # hackage-server run --static-dir=datafiles
#

FROM ubuntu:xenial

RUN apt-get update && \
	apt-get install -y software-properties-common && \
	apt-add-repository ppa:hvr/ghc && \
	apt-get update && \
	apt-get install -y --no-install-recommends \
		cabal-install-2.0 \
		ghc-8.2.1 \
		libicu-dev
		libssl-dev \
		netbase \
		unzip \
		zlib1g-dev

ENV PATH /build/.cabal-sandbox/bin:/opt/ghc/bin:$PATH

# haskell dependencies
RUN mkdir /build
WORKDIR /build
ADD ./hackage-server.cabal ./hackage-server.cabal
RUN cabal update && cabal sandbox init
# TODO: Switch to Nix-style cabal new-install
RUN cabal install --only-dependencies --enable-tests -j --force-reinstalls

# needed for creating TUF keys
RUN cabal install hackage-repo-tool

# add code
# note: this must come after installing the dependencies, such that
# we don't need to rebuilt the dependencies every time the code changes
ADD . /build

# generate keys (needed for tests)
RUN hackage-repo-tool create-keys --keys keys && \
	cp keys/timestamp/*.private datafiles/TUF/timestamp.private && \
	cp keys/snapshot/*.private datafiles/TUF/snapshot.private && \
	hackage-repo-tool create-root --keys keys -o datafiles/TUF/root.json && \
	hackage-repo-tool create-mirrors --keys keys -o datafiles/TUF/mirrors.json

# build & install hackage
RUN cabal configure -f-build-hackage-mirror --enable-tests && cabal build
RUN cabal copy && cabal register

VOLUME /build/state

# setup server runtime environment
CMD hackage-server init --static-dir=datafiles && hackage-server run  --static-dir=datafiles --ip=0.0.0.0
EXPOSE 8080
