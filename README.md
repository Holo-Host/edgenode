# Trailblazer

The DIY image for technical Holo users.

## User Instructions

## Developer Instructions

### Obtaining Private Images

Private images are available from here:
https://github.com/Holo-Host/trailblazer/pkgs/container/trailblazer

`docker login ghcr.io` needs a *classic* github personal access token with `read:packages` access on the Trailblazer repo.  This token will need to be passed instead of the password.

```sh
docker login ghcr.io
docker pull ghcr.io/holo-host/trailblazer
```

### Test for Functional Holochain and hc

```sh
docker run --name trailblazer -dit ghcr.io/holo-host/trailblazer
docker exec -it pioneer /bin/sh
which holochain
which hc
holochain --version
hc --version
lair-keystore --version
```

### Interactive Shell Access

To access an interactive shell in the running container:

```sh
docker exec -it pioneer /bin/sh
```

Or if you want to run commands directly:

```sh
docker exec -it trailblazer holochain --version
docker exec -it trailblazer hc --version
docker exec -it trailblazer lair-keystore --version
```

## Create a Sandbox and Run a Conductor

In an interactive shell, do as follows:

```sh
su - nonroot
hc sandbox create --root /home/nonroot/
```

You need to add webrtc details to the conductor config.

```sh
vi <sandbox_path>/conductor-config.yaml
```

You will need to find the `webrtc_config` stanza and replace it with the following:

```sh
  webrtc_config:
    iceServers:
      - urls:
          - stun:stun.cloudflare.com:3478
      - urls:
          - stun:stun.l.google.com:19302
```

Now you can launch the sandbox!

```sh
hc sandbox run 0
```

Note the `admin_port` displayed after the sandbox is run.  You will also need relevant details for your happ.  

## Scripted hApp install
Now you need another terminal with an interactive shell on the running container.  See previous instructions for how to do that.

Then you will need to perform the following commands:

```sh
su - nonroot
export ADMIN_PORT=<admin_port>
install_happ <config.json> $ADMIN_PORT
```

## Manual hApp install: Kando example
Now you need another terminal with an interactive shell on the running container.  See previous instructions for how to do that.

Then you will need to perform the following commands:

```sh
su - nonroot
export ADMIN_PORT=<admin_port>
export AGENT_KEY=$(hc s -f $ADMIN_PORT call new-agent | awk '{print $NF}')
export APP_ID="kando::v0.13.0::$AGENT_KEY"
wget https://github.com/holochain-apps/kando/releases/download/v0.13.0/kando.happ
export NETWORK_SEED="<network_seed>"
hc s -f $ADMIN_PORT call install-app ./kando.happ $NETWORK_SEED --agent-key "$AGENT_KEY" --app-id "$APP_ID"

```

Kando is now installed in the sandbox.

```sh
hc s -f $ADMIN_PORT call list-apps
hc s -f $ADMIN_PORT call dump-network-stats

```

## Run the Sandbox in Debug Mode

```sh
RUST_LOG=debug hc sandbox run 0
```

### Notes

- The container is designed to stay running with a custom entrypoint script
- Use `-it` flags for interactive terminal access

