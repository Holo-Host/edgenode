FROM cgr.dev/chainguard/wolfi-base

VOLUME ["/data"]

RUN apk update && apk upgrade && apk add --no-cache bash curl wget htop jq strace tcpdump coreutils tini logrotate shadow gosu uuidgen xz libstdc++

ARG HOLOCHAIN_VERSION=0.6.1-rc.3
ARG HC_VERSION=0.6.1-rc.3
ARG TARGETARCH

RUN case "${TARGETARCH}" in \
    amd64) HC_ARCH="x86_64-unknown-linux-gnu" ;; \
    arm64) HC_ARCH="aarch64-unknown-linux-gnu" ;; \
    *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    wget https://github.com/holochain/holochain/releases/download/holochain-${HOLOCHAIN_VERSION}/holochain-${HC_ARCH} && \
    wget https://github.com/holochain/holochain/releases/download/holochain-${HC_VERSION}/hc-${HC_ARCH} && \
    mv holochain-${HC_ARCH} /bin/holochain && \
    mv hc-${HC_ARCH} /bin/hc && \
    chmod +x /bin/holochain && \
    chmod +x /bin/hc

ARG LOG_SENDER_VERSION=0.1.5

RUN case "${TARGETARCH}" in \
    amd64) LS_ARCH="x86_64" ;; \
    arm64) LS_ARCH="aarch64" ;; \
    *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    mkdir -p /usr/local/bin && \
    wget https://github.com/unytco/log-sender/releases/download/v${LOG_SENDER_VERSION}/log-sender-${LS_ARCH} && \
    mv log-sender-${LS_ARCH} /usr/local/bin/log-sender && \
    chmod +x /usr/local/bin/log-sender && \
    mkdir -p /etc/log-sender && \
    chown nonroot:nonroot /etc/log-sender

COPY happ_tool /usr/local/bin/happ_tool
RUN chmod +x /usr/local/bin/happ_tool
RUN ln -sf /usr/local/bin/happ_tool /usr/local/bin/install_happ && \
    ln -sf /usr/local/bin/happ_tool /usr/local/bin/uninstall_happ && \
    ln -sf /usr/local/bin/happ_tool /usr/local/bin/enable_happ && \
    ln -sf /usr/local/bin/happ_tool /usr/local/bin/disable_happ && \
    ln -sf /usr/local/bin/happ_tool /usr/local/bin/list_happs && \
    chmod +x /usr/local/bin/install_happ /usr/local/bin/list_happs /usr/local/bin/uninstall_happ /usr/local/bin/enable_happ /usr/local/bin/disable_happ

COPY log_tool /usr/local/bin/log_tool
RUN chmod +x /usr/local/bin/log_tool

ARG HAPP_CONFIG_FILE_VERSION=0.3.0

RUN case "${TARGETARCH}" in \
    amd64) HCF_ARCH="linux-x86_64" ;; \
    arm64) HCF_ARCH="linux-aarch64" ;; \
    *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    wget "https://github.com/Holo-Host/edgenode/releases/download/tools%2Fhapp_config_file-v${HAPP_CONFIG_FILE_VERSION}/happ_config_file-${HCF_ARCH}" && \
    mv "happ_config_file-${HCF_ARCH}" /usr/local/bin/happ_config_file && \
    chmod +x /usr/local/bin/happ_config_file

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN mkdir -p /usr/local/share/holochain
COPY conductor-config-0.6.1.template.yaml /usr/local/share/holochain/conductor-config.template.yaml
COPY logrotate.d/holochain.conf /etc/logrotate.d/holochain.conf
RUN chown -R nonroot:nonroot /usr/local/share/holochain

SHELL ["/bin/sh", "-c"]
EXPOSE 4444

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
