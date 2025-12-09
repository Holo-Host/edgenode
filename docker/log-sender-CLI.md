# Usage and Command-Line Arguments

The `log-sender` utility has two main subcommands: `init` and `service`.

**`init`**

Initializes a new configuration file. This command generates a new drone cryptographic keypair, registers it with the provided endpoint server, and writes out a config file for operations.

*   `--config-file`: Specify a full path to a config file, e.g. `/var/run/log-sender-runtime.json`. (Env: `LOG_SENDER_CONFIG_FILE`)
*   `--endpoint`: Specify the endpoint url of the log-collector endpoint, e.g. `https://log-collector.my.url`. (Env: `LOG_SENDER_ENDPOINT`)
*   `--unyt-pub-key`: Base64 Unyt Public Key for registration. (Env: `LOG_SENDER_UNYT_PUB_KEY`)
*   `--report-interval-seconds`: Frequency at which to run reporting. (Env: `LOG_SENDER_REPORT_INTERVAL_SECONDS`)
*   `--report-path`: Specify one or more paths to directories that will contain log files with entries to be published as log-collector metrics. The sender will parse all files ending in a `.jsonl` extension. (Env: `LOG_SENDER_REPORT_PATHS`)
*   `--conductor-config-path`: Specify one or more conductor config paths. These will be used to report on database sizes on-disk at the reporting interval. (Env: `LOG_SENDER_CONDUCTOR_CONFIG_PATHS`)

**`service`**

Runs the service, polling a log-file directory for metrics to publish to the log-collector.

*   `--config-file`: Specify a full path to a config file, e.g. `/var/run/log-sender-runtime.json`. (Env: `LOG_SENDER_CONFIG_FILE`)

*   
**`register-dna`**

Register DNA hashes with agreements and optional price sheets for a drone.

*   `--config-file`: Specify a full path to a config file, e.g. `/var/run/log-sender-runtime.json`. (Env: `LOG_SENDER_CONFIG_FILE`)
*   --dna-hash "uhC0kgP43a9niFkCJKDQvPXVgrvEre4W6ZOALK7urTxw4eba2KHj6"
*   --agreement-id "uhCkk0shdgubeywhKm71XEH6Qzl4Me2iLQDkybETd7Nd_iUpMNnbW"
*   --price_sheet_hash: Option<String>
*   --LOG_SENDER_METADATA
