# Heroku Tailscale PostgreSQL Buildpack

A narrowly scoped Heroku buildpack that:

1. runs Tailscale in userspace networking mode;
2. registers each dyno as an ephemeral, tagged Tailscale node using an OAuth client secret;
3. exposes one local TCP endpoint for PostgreSQL; and
4. runs the application without ProxyChains or global proxy environment variables.

It deliberately does **not** intercept all process networking, rewrite Rails executables, modify `ALL_PROXY`, or start automatically from `.profile.d`.

## Architecture

```text
Rails / Sidekiq / psql
        |
        | TCP 127.0.0.1:15432
        v
      gost
        |
        | SOCKS5 127.0.0.1:1055
        v
 tailscaled --tun=userspace-networking
        |
        | encrypted tailnet connection
        v
subnet router or Tailscale host -> PostgreSQL:5432
```

TLS remains end-to-end between libpq and PostgreSQL. `gost` and Tailscale only carry the byte stream.

## Authentication terminology

This buildpack uses a Tailscale **OAuth client secret**, not an OIDC key. Tailscale accepts an OAuth client secret directly as `tailscale up --auth-key=...` when the client has the `auth_keys` scope and authorized tags. OAuth-registered devices are ephemeral by default.

Federated OIDC workload identity would avoid a long-lived secret, but requires the hosting platform to issue a suitable workload identity token. This buildpack does not assume Heroku provides one.

## Tailnet setup

Create a dedicated source tag, for example:

```json
{
  "tagOwners": {
    "tag:heroku-xbe-prod": ["group:platform"]
  },
  "grants": [
    {
      "src": ["tag:heroku-xbe-prod"],
      "dst": ["10.40.2.15"],
      "ip": ["tcp:5432"]
    }
  ]
}
```

Create an OAuth client with:

- scope: `auth_keys`;
- tag: `tag:heroku-xbe-prod` only.

Do not grant broad device-management scopes or unrelated tags.

## Install

Add this buildpack before the language buildpack or test both orders in staging:

```bash
heroku buildpacks:add --index 1 https://github.com/x-b-e/heroku-tailscale-postgres-buildpack
```

Set configuration:

```bash
heroku config:set \
  TS_OAUTH_SECRET='tskey-client-...' \
  TS_TAGS='tag:heroku-xbe-prod' \
  PRIVATE_DATABASE_HOST='10.40.2.15' \
  PRIVATE_DATABASE_PORT='5432' \
  LOCAL_DATABASE_PORT='15432'
```

Do not enable shell tracing around `TS_OAUTH_SECRET`.

## Application database configuration

Point libpq at the local listener. Preserve the real database hostname separately when using `sslmode=verify-full`.

Rails `database.yml` example:

```yaml
production:
  adapter: postgresql
  host: <%= ENV.fetch("DATABASE_TLS_HOST") %>
  hostaddr: 127.0.0.1
  port: <%= ENV.fetch("LOCAL_DATABASE_PORT", 15432) %>
  database: <%= ENV.fetch("DATABASE_NAME") %>
  username: <%= ENV.fetch("DATABASE_USERNAME") %>
  password: <%= ENV.fetch("DATABASE_PASSWORD") %>
  sslmode: verify-full
  sslrootcert: <%= ENV.fetch("DATABASE_SSL_ROOT_CERT") %>
  connect_timeout: 5
  keepalives: 1
  keepalives_idle: 30
  keepalives_interval: 10
  keepalives_count: 3
```

`hostaddr` controls the TCP destination; `host` remains the hostname checked against the server certificate.

## Procfile

Wrap only process types that need the private database:

```procfile
web: bin/with-tailscale-postgres bundle exec puma -C config/puma.rb
worker: bin/with-tailscale-postgres bundle exec sidekiq
release: bin/with-tailscale-postgres bundle exec rails db:migrate
```

A process not using the wrapper has ordinary Heroku networking and does not create a Tailscale node.

## Configuration

| Variable | Required | Default | Purpose |
|---|---:|---|---|
| `TS_OAUTH_SECRET` | yes | | OAuth client secret with `auth_keys` scope |
| `TS_TAGS` | yes | | Comma-separated authorized tags |
| `PRIVATE_DATABASE_HOST` | yes | | Tailnet IP or private IP reachable through a subnet router |
| `PRIVATE_DATABASE_PORT` | no | `5432` | Remote PostgreSQL port |
| `LOCAL_DATABASE_HOST` | no | `127.0.0.1` | Local bind address; do not use `0.0.0.0` |
| `LOCAL_DATABASE_PORT` | no | `15432` | Local PostgreSQL port |
| `TS_SOCKS_HOST` | no | `127.0.0.1` | Local SOCKS bind address |
| `TS_SOCKS_PORT` | no | `1055` | Local SOCKS port |
| `TS_HOSTNAME` | no | Heroku app/dyno | Tailscale device name |
| `TS_UP_TIMEOUT` | no | `20s` | `tailscale up` timeout |
| `STARTUP_TIMEOUT_SECONDS` | no | `30` | Forwarder startup timeout |
| `VERIFY_DATABASE_CONNECTION` | no | `true` | Run `pg_isready` when available |
| `TAILSCALE_VERSION` | build | `1.80.2` | Pinned Tailscale version |
| `GOST_VERSION` | build | `3.2.6` | Pinned gost version; checksums currently cover 3.2.6 |

Changing `GOST_VERSION` requires updating the pinned SHA-256 values in `bin/compile`.

## Failure behavior

The application does not start unless:

- `tailscaled` is running;
- the dyno has joined the tailnet;
- `gost` is listening locally; and
- PostgreSQL answers `pg_isready`, when that command is installed and verification is enabled.

If the application exits, the wrapper exits with the same status. On `TERM` or `INT`, the wrapper forwards the signal and stops the forwarder and Tailscale daemon.

## Security properties

- The local database listener binds only to `127.0.0.1` by default.
- No process-wide `LD_PRELOAD`, ProxyChains, `ALL_PROXY`, or DNS interception.
- Ephemeral nodes reduce stale device accumulation.
- The OAuth client can be restricted to one tag.
- Tailscale and gost downloads are checksum-verified.
- PostgreSQL TLS should remain enabled, preferably `verify-full`.

The OAuth secret is still a long-lived credential. Store it as a Heroku config var, restrict who can read app configuration, rotate it, and revoke it immediately after suspected exposure.

## Testing

Run the shell test suite:

```bash
bash tests/run
```

Run linting when ShellCheck is installed:

```bash
shellcheck bin/* lib/* tests/run
```

### Staging integration test

Use a non-production PostgreSQL endpoint and a staging-only tag. Then run:

```bash
heroku run 'bin/with-tailscale-postgres psql "$DATABASE_URL" -c "select 1"' --app APP
```

Test at least:

1. successful web and worker startup;
2. bad OAuth secret;
3. denied tailnet ACL;
4. unreachable subnet router;
5. PostgreSQL restart;
6. dyno `SIGTERM` and graceful shutdown;
7. preboot deploy with old and new dynos overlapping;
8. release-phase migrations;
9. one-off console behavior;
10. recovery of ActiveRecord pools after the tunnel is interrupted.

## Updating dependencies

1. Choose a tested Tailscale stable version.
2. Confirm its `.sha256` file exists on `pkgs.tailscale.com`.
3. Choose a stable gost release.
4. Replace the gost version and architecture checksums together.
5. Run tests and staging failure drills.
6. Deploy by immutable Git commit SHA rather than a moving branch URL.

## Why not nginx?

nginx in front of Puma handles inbound HTTP. It does not create private outbound database routing. Its stream module could act as a TCP forwarder, but it would still need the same SOCKS/Tailscale bridge and would add unnecessary configuration.
