FROM debian:bookworm-slim
LABEL maintainer="Yostin Vargas"

# BuildKit sets TARGETARCH (amd64 / arm64 / arm), matching mkcert's release names.
ARG TARGETARCH
ARG MKCERT_VERSION=v1.4.4

RUN apt-get -qq update \
    && apt-get -yqq --no-install-recommends install ca-certificates curl \
    && curl -fsSL \
        "https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VERSION}/mkcert-${MKCERT_VERSION}-linux-${TARGETARCH}" \
        -o /usr/local/bin/mkcert \
    && chmod +x /usr/local/bin/mkcert \
    && apt-get -yqq purge curl \
    && apt-get -qqy autoremove \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# The CA lives on a mounted volume so it survives between runs.
ENV CAROOT=/caroot

ENTRYPOINT ["mkcert"]
