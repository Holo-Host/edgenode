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

### Quick One Off Test for Functional Image
`docker run -it --rm ghcr.io/holo-host/pioneer:1756983968`

### Test for Functional Holochain and hc
```
docker run --name pioneer -dit ghcr.io/holo-host/pioneer:1756983968
docker exec -it pioneer sh
which holochain
which hc
holochain --version
hc --version
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
```

### Notes
- The container is designed to stay running with a custom entrypoint script
- Use `-it` flags for interactive terminal access
- The entrypoint script displays version information on container start

