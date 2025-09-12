# Known Issues

## Failing WebRTC Connection with Docker Desktop with Windows/WSL2   
```
    # Conditional TURN fallback for WSL2
    {% if 'Microsoft' in open('/proc/version').read() %}
    - urls: ["turn:localhost:3478?transport=udp"]
      username: "holo"
      credential: "${TURN_SECRET}"
    {% endif %}
```