# happ_config_file

A CLI for creating and validating JSON configuration files used by Edge Node tools.

## Build

Requires Rust.

```bash
cargo build --release
```

Binary: `target/release/happ_config_file`

## Usage

```bash
happ_config_file <COMMAND>
```

Commands:

- create — write a config file template
- validate — check a config file for structure and basic rules

### create

```bash
happ_config_file create [--name <app_name>] [--gateway] [--economics] [--init-zome-calls] [--iroh]
```

Options:

- --name <app_name>: Optional name to use for app.name; output file will be `<app_name>_config.json`. Name must match `[a-z0-9_]+`.
- --gateway: Include optional env.gw section
- --economics: Include optional economics section
- --init-zome-calls: Include example app.init_zome_calls block
- --iroh: Generate an iroh networking config (HC >= 0.6.1 default backend). Emits `relayUrl` instead of `signalServerUrl`/`stunServerUrls`.

Behavior:

- If `--name` is provided, the generated file is `<name>_config.json` and `app.name` is set to `<name>`.
- If `--name` is omitted, the generated file is `example_happ_config.json` and `app.name` is `example_happ`.
- Optional sections are omitted if the flags are not provided.
- Without `--iroh`, the template uses the WebRTC/go-pion networking fields (`signalServerUrl`, `stunServerUrls`).
- With `--iroh`, the template uses the iroh networking field (`relayUrl`) and omits WebRTC fields.

### validate

```bash
happ_config_file validate --input ./config.json
```

- Validates structure and selected fields (URLs, app name pattern, semver).
- Accepts configs that omit env.gw, economics, and app.init_zome_calls.
- Accepts both WebRTC-style configs (`signalServerUrl`, `stunServerUrls`) and iroh-style configs (`relayUrl`).
- app.modifiers.networkSeed can be any string (including empty).

## Networking backends

### WebRTC / go-pion (HC <= 0.6.0)

```json
"holochain": {
  "version": "",
  "flags": [""],
  "bootstrapUrl": "",
  "signalServerUrl": "",
  "stunServerUrls": [""]
}
```

### iroh (HC >= 0.6.1 default backend)

```json
"holochain": {
  "version": "",
  "flags": [""],
  "bootstrapUrl": "",
  "relayUrl": ""
}
```

## Minimal JSON (no optional sections, iroh backend)

```json
{
  "app": {
    "name": "example_happ",
    "version": "0.1.0",
    "happUrl": "https://github.com/example/v0.1.0/example_happ.happ",
    "modifiers": { "networkSeed": "", "properties": "" }
  },
  "env": {
    "holochain": {
      "version": "",
      "flags": [""],
      "bootstrapUrl": "",
      "relayUrl": ""
    }
  }
}
```

## Examples

```bash
# Create with an explicit name; writes my_app_config.json with app.name = "my_app"
happ_config_file create --name my_app --gateway --economics --init-zome-calls

# Create with defaults; writes example_happ_config.json with app.name = "example_happ"
happ_config_file create

# Create an iroh-based config (HC >= 0.6.1)
happ_config_file create --iroh --name my_app

# Validate a file (works for both WebRTC and iroh configs)
happ_config_file validate --input ./example_happ_config.json
```
