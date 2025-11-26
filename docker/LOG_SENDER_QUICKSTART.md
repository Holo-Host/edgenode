# Log-Sender Quickstart 

## Quick Start

See the [Docker README.md](/README.md) for the basics on Edge Node Container Setup and you will need to be using `Dockerfile.unyt` as the template for your Unyt-based Edge Node container image.
See the [Log-sender](https://github.com/unytco/log-sender/blob/main/LOG_SENDER_USER_GUIDE.md) for detailed usage guide.

**Prerequisites:**

- Holochain 0.6.0 conductor with reporting enabled
- Access to Holochain agent key (unyt public key)
- Log-collector service endpoint
- Log directories where Holochain conductor writes JSONL files

### 1. Basic Setup

```bash
# Initialize configuration with your log-collector endpoint
# Use your Holochain agent's unyt public key
log-sender init \
  --config-file /etc/log-sender/config.json \
  --endpoint http://log-collector.example.com:8787 \
  --unyt-pub-key uhCAk... \
  --report-interval-seconds 60 \
  --report-path /var/log/holochain \
  --conductor-config-path /etc/holochain/conductor-config.toml

# Start the service
log-sender service --config-file /etc/log-sender/config.json
```

### 2. Running as a Service

The `log-sender` is automatically started as a service by `supervisord` when the container starts. You can check the status of the service by running the following command:

```bash
supervisorctl status
```

You can also view the logs for the `log-sender` service with the following command:

```bash
tail -f /data/logs/log-sender.log
```
