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
docker exec -dit pioneer sh
which holochain
which hc
holochain --version
hc --version
```

