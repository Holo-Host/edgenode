# Known Issues

## Peer connectivity behind symmetric NAT (Docker Desktop on Windows/WSL2)
Holochain 0.7 uses the iroh QUIC transport. Direct peer connections may still fail behind the symmetric NAT of the WSL2 virtual network; traffic then falls back to the configured `relay_url`. If nodes never see peers, confirm outbound UDP is permitted and that the relay URL in `/etc/holochain/conductor-config.yaml` is reachable.
