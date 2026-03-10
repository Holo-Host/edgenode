# Log-Sender E2E Testing Guide

## Process Flow

### 1. Initialization (`log-sender init`)

1. Validates endpoint and unyt public key
2. Generates 2048-bit RSA keypair for device identity
3. Registers drone with log-collector (POST to `/register`)
4. Writes config file with assigned `drone_id` and keys

### 2. DNA Registration (`log-sender register-dna`)

Associates a DNA hash with a Unyt agreement for accounting.

### 3. Service Loop (`log-sender service`)

1. Loads config (drone_id, keys, paths)
2. Scans report directories for `.jsonl` files
3. Parses entries (requires `k` and `t` fields)
4. Signs and submits to `/metrics` endpoint
5. Sleeps for configured interval, repeats

### Log Format (JSONL)

```json
{"k":"start","t":"1758571617392359","namespace":"my-app","status":"initialized"}
{"k":"fetchedOps","t":"1758571617392360","count":150,"latency":42}
```

Required fields:
- `k` (kind): Log type identifier
- `t` (timestamp): Microseconds as string

## Keys

| Key | Source | Format |
|-----|--------|--------|
| Unyt public key | Holochain agent key | `uhCAk...` |
| Drone public key | Generated at init | Base64 SPKI DER |
| Drone secret key | Generated at init | Base64 PKCS8 DER |

## BATS Testing

Tests focus on end-to-end user workflows, not internal APIs.

```bash
# Init test
run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
    --config-file /etc/log-sender/config.json \
    --endpoint "$LOG_COLLECTOR_URL" \
    --unyt-pub-key "$UNYT_PUB_KEY" \
    --report-interval-seconds 2
assert_success

# Verify registration
docker compose exec -T -u nonroot "$SERVICE_NAME" \
    jq -r '.drone_id' /etc/log-sender/config.json

# Create test data (timestamps must be microseconds)
local current_time=$(($(date +%s) * 1000000))
echo "{\"k\":\"metric\",\"t\":\"$current_time\",\"value\":100}" > test.jsonl

# Run service with timeout
run docker compose exec -T -u nonroot "$SERVICE_NAME" \
    timeout 15 log-sender service --config-file /etc/log-sender/config.json
```

## Common Issues

- **Timestamps must be microseconds**: `$(date +%s) * 1000000`, not milliseconds
- **Key format**: log-sender uses SPKI DER (not PEM) for public keys
- **JSONL validation**: Every line must be valid JSON with `k` and `t` fields
- **Network**: Verify log-collector is reachable from the container (`curl http://log-collector:8787/`)
