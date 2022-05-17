ARG ASKAR_VERSION=0.2.6
ARG INDY_CREDX_VERSION=0.3.1
ARG ACAPY_VERSION=0.7.3
ARG INDY_SDK_VERSION=1.16.0
ARG RELEASE=release

FROM debian:buster-slim AS resources

ARG ASKAR_VERSION
ARG INDY_CREDX_VERSION
ARG ACAPY_VERSION
ARG INDY_SDK_VERSION

WORKDIR /resources

RUN apt-get update && apt-get install -y curl && apt-get clean
RUN curl -L https://github.com/hyperledger/aries-askar/archive/refs/tags/v${ASKAR_VERSION}.tar.gz -o askar.tar.gz
RUN curl -L https://github.com/hyperledger/indy-shared-rs/archive/refs/tags/v${INDY_CREDX_VERSION}.tar.gz -o indy-credx.tar.gz
RUN curl -L https://github.com/hyperledger/aries-cloudagent-python/archive/refs/tags/${ACAPY_VERSION}.tar.gz -o acapy.tar.gz
RUN curl -L https://github.com/hyperledger/indy-sdk/archive/refs/tags/v${INDY_SDK_VERSION}.tar.gz -o indy-sdk.tar.gz

FROM rust:1.60.0-slim-buster AS askar
ARG RELEASE
WORKDIR /askar
COPY --from=resources /resources/askar.tar.gz .
RUN tar xzf askar.tar.gz --strip-components=1 && \
        if [ "${RELEASE}" = "release" ]; then cargo build --release; else cargo build; fi

FROM rust:1.60.0-slim-buster AS indy-credx
ARG RELEASE
WORKDIR /indy-credx
COPY --from=resources /resources/indy-credx.tar.gz .
RUN apt-get update && apt-get install -y libssl-dev pkg-config && apt-get clean
RUN tar xzf indy-credx.tar.gz --strip-components=1 && \
        if [ "${RELEASE}" = "release" ]; then cargo build --release; else cargo build; fi

FROM rust:1.46.0-slim-buster AS indy-sdk
ARG RELEASE
WORKDIR /indy-sdk
COPY --from=resources /resources/indy-sdk.tar.gz .
RUN apt-get update && apt-get install -y libssl-dev pkg-config libsodium-dev libzmq3-dev && apt-get clean
RUN tar xzf indy-sdk.tar.gz --strip-components=1
RUN if [ "${RELEASE}" = "release" ]; then RELEASE_ARGS="--release"; else RELEASE_ARGS=""; fi && \
        cargo build ${RELEASE_ARGS} --manifest-path=libindy/Cargo.toml
RUN cp libindy/target/${RELEASE}/libindy.so /usr/lib
RUN if [ "${RELEASE}" = "release" ]; then RELEASE_ARGS="--release"; else RELEASE_ARGS=""; fi && \
        cargo build ${RELEASE_ARGS} --manifest-path=experimental/plugins/postgres_storage/Cargo.toml

FROM python:3.10-slim-buster AS acapy
ARG ACAPY_VERSION
ARG RELEASE
RUN useradd -ms /bin/bash aries
WORKDIR /home/aries
COPY --from=askar /askar/target/${RELEASE}/libaries_askar.so /usr/lib
COPY --from=indy-credx /indy-credx/target/${RELEASE}/libindy_credx.so /usr/lib
COPY --from=indy-sdk /indy-sdk/libindy/target/${RELEASE}/libindy.so /usr/lib
COPY --from=indy-sdk /indy-sdk/experimental/plugins/postgres_storage/target/${RELEASE}/libindystrgpostgres.so /usr/lib
RUN apt-get update && apt-get install -y libsodium-dev libzmq3-dev && apt-get clean
COPY --from=resources /resources/acapy.tar.gz .
RUN tar xzf acapy.tar.gz --strip-components=1 && \
        pip install -e .[askar,bbs,indy] && \
        rm acapy.tar.gz
RUN rm /usr/local/lib/python3.10/site-packages/aries_askar/libaries_askar.so
RUN rm /usr/local/lib/python3.10/site-packages/indy_credx/libindy_credx.so
RUN chown -R aries:aries .
USER aries

ENTRYPOINT ["aca-py"]
