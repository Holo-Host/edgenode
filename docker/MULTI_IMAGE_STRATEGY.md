# Multi-Image Docker Strategy

## Supported Images

| Image | Dockerfile | Base | Log-Collector |
|-------|-----------|------|---------------|
| hc-0.5.6 | `Dockerfile.hc-0.5.6` | wolfi-base | No |
| hc-0.6.0-go-pion | `Dockerfile.hc-0.6.0-go-pion` | wolfi-base | No |
| hc-0.6.1 | `Dockerfile.hc-0.6.1-rc.1` | wolfi-base | No |
| unyt | `Dockerfile.unyt` | hc-0.6.1 | Yes (required) |

## Compose Files

```
docker-compose.base.yml              # Common networks/volumes
docker-compose.hc-0.5.6.yml          # HC 0.5.6 service
docker-compose.hc-0.6.0-dev-go-pion.yml  # HC 0.6.0 service
docker-compose.hc-0.6.1.yml          # HC 0.6.1 service
docker-compose.unyt.yml              # UNYT service + log-collector
docker-compose.yml                   # Simple dev setup
```

Combine as needed:

```bash
# HC 0.5.6
docker compose -f docker-compose.base.yml -f docker-compose.hc-0.5.6.yml up

# UNYT with log-collector
docker compose -f docker-compose.base.yml -f docker-compose.unyt.yml up
```

## Building

```bash
# Build specific image
./build-images.sh Dockerfile.hc-0.6.1-rc.1
./build-images.sh Dockerfile.unyt

# Build all
./build-images.sh all
```

The script handles dependencies automatically (e.g., builds hc-0.6.1 before unyt if needed).

## Testing

```bash
./run_tests_multi.sh local-edgenode-hc-0.5.6
./run_tests_multi.sh local-edgenode-hc-0.6.1
./run_tests_multi.sh local-edgenode-unyt
```

Tests use `$SERVICE_NAME` for dynamic service discovery across image variants.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `EDGENODE_IMAGE` | Override default image name |
| `SERVICE_NAME` | Dynamic service name for tests (auto-set) |
| `CONDUCTOR_MODE` | True by default |
| `ADMIN_SECRET` | Log collector admin secret |
| `RUST_LOG` | Log level |

UNYT-specific:

| Variable | Description |
|----------|-------------|
| `LOG_SENDER_UNYT_PUB_KEY` | Unyt public key |
| `LOG_SENDER_ENDPOINT` | Log collector endpoint |
| `LOG_SENDER_REPORT_INTERVAL_SECONDS` | Reporting frequency |
| `LOG_SENDER_LOG_PATH` | Report file path |

## Troubleshooting

```bash
# Missing base image for unyt
./build-images.sh Dockerfile.hc-0.6.1-rc.1
./build-images.sh Dockerfile.unyt

# Check services
docker compose -f docker-compose.base.yml -f docker-compose.unyt.yml ps

# View logs
docker compose -f docker-compose.base.yml -f docker-compose.unyt.yml logs edgenode-unyt
```

When using `env -i` in tests, preserve PATH: `env -i PATH="$PATH" VAR=value ...`
