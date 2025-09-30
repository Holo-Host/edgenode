FROM cgr.dev/chainguard/wolfi-base

VOLUME ["/data"]

RUN apk update && apk add --no-cache --update-cache bash curl wget htop jq strace tcpdump coreutils tini logrotate shadow gosu

RUN wget https://github.com/matthme/holochain-binaries/releases/download/holochain-binaries-0.5.6/holochain-v0.5.6-x86_64-unknown-linux-gnu && wget https://github.com/matthme/holochain-binaries/releases/download/hc-binaries-0.5.6/hc-v0.5.6-x86_64-unknown-linux-gnu && mv holochain-v0.5.6-x86_64-unknown-linux-gnu /bin/holochain && mv hc-v0.5.6-x86_64-unknown-linux-gnu /bin/hc && chmod +x /bin/holochain && chmod +x /bin/hc
RUN wget https://github.com/matthme/holochain-binaries/releases/download/lair-binaries-0.6.2/lair-keystore-v0.6.2-x86_64-unknown-linux-gnu && mv lair-keystore-v0.6.2-x86_64-unknown-linux-gnu /bin/lair-keystore && chmod +x /bin/lair-keystore

# Copy and set up happ tool script
COPY happ_tool /usr/local/bin/happ_tool
RUN chmod +x /usr/local/bin/happ_tool
RUN ln -sf /usr/local/bin/happ_tool /usr/local/bin/install_happ && \
    ln -sf /usr/local/bin/happ_tool /usr/local/bin/list_happs && \
    chmod +x /usr/local/bin/install_happ /usr/local/bin/list_happs

# Copy and set up happ_config_file
COPY happ_config_file /usr/local/bin/happ_config_file 
RUN chmod +x /usr/local/bin/happ_config_file

# Copy and set up entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Copy and set up holochain paths and files.  
RUN mkdir -p /usr/local/share/holochain
COPY conductor-config.template.yaml /usr/local/share/holochain/conductor-config.template.yaml
COPY logrotate.d/holochain.conf /etc/logrotate.d/holochain.conf
RUN chown -R nonroot:nonroot /usr/local/share/holochain

SHELL ["/bin/sh", "-c"]
EXPOSE 4444

# Set entrypoint to keep container running and allow interactive shell access
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
