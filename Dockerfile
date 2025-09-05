FROM cgr.dev/chainguard/wolfi-base

RUN apk update && apk add --no-cache --update-cache curl wget htop jq
RUN wget https://github.com/matthme/holochain-binaries/releases/download/holochain-binaries-0.5.6/holochain-v0.5.6-x86_64-unknown-linux-gnu && wget https://github.com/matthme/holochain-binaries/releases/download/hc-binaries-0.5.6/hc-v0.5.6-x86_64-unknown-linux-gnu && mv holochain-v0.5.6-x86_64-unknown-linux-gnu /bin/holochain && mv hc-v0.5.6-x86_64-unknown-linux-gnu /bin/hc && chmod +x /bin/holochain && chmod +x /bin/hc

SHELL ["/bin/sh", "-c"]

# Copy and set up entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Set entrypoint to keep container running and allow interactive shell access
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
