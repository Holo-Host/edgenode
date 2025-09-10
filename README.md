# pioneer

The DIY image for technical Holo users.

## User Instructions

## Developer Instructions

### Obtaining Private Images

Private images are available from here:
https://github.com/Holo-Host/pioneer/pkgs/container/pioneer

`docker login ghcr.io` needs a *classic* github personal access token with `read:packages` access on the Pioneer repo.  This token will need to be passed instead of the password.

```sh
docker login ghcr.io
docker pull ghcr.io/holo-host/pioneer
```

### Quick One Off Test for Functional Image

To just run it:

```sh
docker run -it --rm ghcr.io/holo-host/pioneer
```

To use either a specific version tag or `:latest`:

```sh
docker run -it --rm ghcr.io/holo-host/pioneer:<tag>
```

or

```sh
docker run -it --rm ghcr.io/holo-host/pioneer:latest
```

### Test for Functional Holochain and hc

```sh
docker run --name pioneer -dit ghcr.io/holo-host/pioneer
docker exec -it pioneer sh
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
docker exec -it pioneer holochain --version
docker exec -it pioneer hc --version
docker exec -it pioneer lair-keystore --version
```

## Create a Sandbox and Run a Conductor

In an interactive shell, do as follows:

```sh
su nonroot
cd 
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

```sh
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
- The entrypoint script displays version information on container start

