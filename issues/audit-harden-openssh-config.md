### Audit and harden OpenSSH configuration

After build, review and update /etc/ssh/sshd_config to enforce security best practices: 
- Disable password authentication if possible
- Require key-based auth
- Restrict root login

Ensure only necessary features are enabled.