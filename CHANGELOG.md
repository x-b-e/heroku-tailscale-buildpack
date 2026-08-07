# Changelog

## 1.0.0

- Replace process-wide ProxyChains with a PostgreSQL-only local TCP forward.
- Use Tailscale userspace networking and ephemeral OAuth-client registration.
- Add checksum verification, explicit process wrapping, health checks, signal handling, tests, and CI.
