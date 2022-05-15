ARG ASKAR_VERSION=0.2.6
ARG INDY_CREDX_VERSION=0.3.1
ARG ACAPY_VERSION=0.7.3
ARG RELEASE=release

FROM debian:buster-slim AS resources

ARG ASKAR_VERSION
ARG INDY_CREDX_VERSION
ARG ACAPY_VERSION

WORKDIR /resources

RUN apt update && apt install -y curl && apt clean
RUN curl -L https://github.com/hyperledger/aries-askar/archive/refs/tags/v${ASKAR_VERSION}.tar.gz -o askar.tar.gz
RUN curl -L https://github.com/hyperledger/indy-shared-rs/archive/refs/tags/v${INDY_CREDX_VERSION}.tar.gz -o indy-credx.tar.gz
RUN curl -L https://github.com/hyperledger/aries-cloudagent-python/archive/refs/tags/${ACAPY_VERSION}.tar.gz -o acapy.tar.gz

FROM rust:1.60.0-slim-buster AS askar
ARG ASKAR_VERSION
ARG RELEASE
WORKDIR /askar
COPY --from=resources /resources/askar.tar.gz .
RUN tar xzvf askar.tar.gz && \
        cd aries-askar-${ASKAR_VERSION} && \
        if [ "${RELEASE}" = "release" ]; then cargo build --release; else cargo build; fi

FROM rust:1.60.0-slim-buster AS indy-credx
ARG INDY_CREDX_VERSION
WORKDIR /indy
COPY --from=resources /resources/indy-credx.tar.gz .
RUN apt update && apt install -y libssl-dev pkg-config && apt clean
RUN tar xzvf indy-credx.tar.gz && \
        cd indy-shared-rs-${INDY_CREDX_VERSION} && \
        if [ "${RELEASE}" = "release" ]; then cargo build --release; else cargo build; fi

FROM python:3.10-slim-buster AS acapy
ARG ASKAR_VERSION
ARG INDY_CREDX_VERSION
ARG ACAPY_VERSION
ARG RELEASE
RUN useradd -ms /bin/bash aries
WORKDIR /home/aries
COPY --from=resources /resources/acapy.tar.gz .
RUN tar xzvf acapy.tar.gz --strip-components=1 && pip install -e .[askar,bbs] && rm acapy.tar.gz
COPY --from=askar /askar/aries-askar-${ASKAR_VERSION}/target/${RELEASE}/libaries_askar.so /usr/local/lib/python3.10/site-packages/aries_askar/libaries_askar.so
COPY --from=indy-credx /indy/indy-shared-rs-${INDY_CREDX_VERSION}/target/${RELEASE}/libindy_credx.so /usr/local/lib/python3.10/site-packages/indy_credx/libindy_credx.so
RUN chown -R aries:aries .
USER aries

ENTRYPOINT ["aca-py"]
