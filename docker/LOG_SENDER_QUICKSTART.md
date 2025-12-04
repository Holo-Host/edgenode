# Log-Sender integration
An Edge Node container featuring:
- `log-sender` binary that can deliver standard holochain reports to a specific location , 
- Unyt specific configuration.
- Scripts for initializing and configuring your version of `log-sender`.
- Scripts for registering the dna of Unyt based happs (e.g. Circulo).
- A CLI utility for initializing log-sender and registering your happ DNA (with Unyt based happs).

## Quick Start

See the [Docker README.md](/README.md) for the basics on Edge Node Container Setup and you will need to be using [Dockerfile.unyt](/Dockerfile.unyt) as the template for your Unyt-based Edge Node container image.

For detailed user guide see the [Log-sender](https://github.com/unytco/log-sender/blob/main/LOG_SENDER_USER_GUIDE.md) .


**Prerequisites:**

- Holochain 0.6.0 conductor with reporting enabled.
- Access to your Unyt agent public key.
- Log-collector service endpoint.
- Log directories where Holochain conductor writes JSONL files (var/local/lib/holochain/reports by default).
- An installed happ which has an agreemnt setup in Unyt.

### 1. Pull log-sender enabled image

```bash
docker run --name unytnode -dit \
  -v $(pwd)/holo-data:/data \
  ghcr.io/holo-host/edgenode:v0.0.8-alpha29-unyt
```

### 2. Basic Setup

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

# Register a DNA confirm the DNA hash and agreement id
log-sender register-dna \
--config-file /etc/log-sender/config.json \
--dna-hash "uhC0kFLU..." \
--agreement-id "uhCkk9zj..."

# Start the service
log-sender service --config-file /etc/log-sender/config.json
```
See [here](/log-sender-CLI.md) for more details.
### 3. Running as a Service

The `log-sender` is automatically started as a service by `supervisord` when the container starts. You can check the status of the service by running the following command:

```bash
supervisorctl status
```

You can also view the logs for the `log-sender` service with the following command:

```bash
tail -f /data/logs/log-sender.log
```
