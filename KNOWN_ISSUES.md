# Known Issues

## Failing WebRTC Connection with Docker Desktop with Windows/WSL2   
Due to the symmetric NAT that is incorporated into the WSL virtual network stack, WebRTC connections from the container will fail.

We do not have a solution at this time and welcome pull requests that could address this.