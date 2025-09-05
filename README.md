# pioneer
The DIY image for technical Holo users.

## User Instructions



## Developer Instructions
### Obtaining Private Images
Private images are available from here:
https://github.com/Holo-Host/pioneer/pkgs/container/pioneer

`docker login` needs a *classic* github personal access token with `read:packages` access on the Pioneer repo.

```
docker login ghcr.io
docker pull ghcr.io/holo-host/pioneer:<tag>
```

**Note:** The `:latest` tag is also available for the most recent build:
```
docker pull ghcr.io/holo-host/pioneer:latest
```

### Quick One Off Test for Functional Image
Use either the specific version tag or `:latest`:
```
docker run -it --rm ghcr.io/holo-host/pioneer:<tag>
```
or
```
docker run -it --rm ghcr.io/holo-host/pioneer:latest
```

### Test for Functional Holochain and hc
```
docker run --name pioneer -dit ghcr.io/holo-host/pioneer:latest
docker exec -it pioneer sh
which holochain
which hc
holochain --version
hc --version
lair-keystore --version
```

### Interactive Shell Access
To access an interactive shell in the running container:
```
docker exec -it pioneer /bin/sh
```

Or if you want to run commands directly:
```
docker exec -it pioneer holochain --version
docker exec -it pioneer hc --version
docker exec -it pioneer lair-keystore --version
```

## Creating a Conductor Configuration
```
su nonroot
holochain --create-config
```
Take a note of the path for the resulting `conductor-config.yaml`

## Creating a Sandbox
```
hc sandbox create --root /home/nonroot/
```

Take a note of the path for the resulting `conductor-config.yaml`

### Notes
- The container is designed to stay running with a custom entrypoint script
- Use `-it` flags for interactive terminal access
- The entrypoint script displays version information on container start

