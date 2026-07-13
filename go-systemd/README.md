# Deploy Go App with systemd

## Initial Deployment - Non Container

Brief instruction to setup a VPS for deploying a Go binary managed by systemd, using:

- Go binary (pre-built, uploaded via CI/CD)
- systemd service
- ACL (for deployer permissions)
- Redis (optional)
- Chromium + bun + Lighthouse (optional, for lighthouse worker use case)
- Lightpanda headless browser (optional)

> [!WARNING]
> You must run these steps as a root user or user with sudo access.

1. Create [a droplet in Digital Ocean](https://m.do.co/c/303e46500afd) with latest Ubuntu LTS.

2. Once droplet created, create an `A record` pointing the droplet's public IP to your domain in DNS (e.g. Cloudflare). Set proxy status to **DNS only**.

| Type | Name                    | Content           | Proxy Status | TTL    |
|:-----|:------------------------|:------------------|:-------------|:-------|
| A    | <env>.<app-name>        | droplet-ip-public | DNS only     | &nbsp; |

3. Run `setup.sh` on the droplet. It does:

- Configure UFW (allow OpenSSH)
- Install ACL
- Install Redis server or redis-cli (optional)
- Install ungoogled-chromium portable + bun + Lighthouse (optional)
- Install Lightpanda headless browser (optional)
- Create `deployer` user
- Create SSH key pair for `deployer`
- Create deploy directory at `/opt/<env>.<app-name>` with ACL permissions for `deployer`
- Enable `network-online.target` for systemd service ordering
- Display SSH key info for CI/CD setup

**Quick install** (downloads and runs `setup.sh` via `install.sh`):

```sh
curl -fsSL https://raw.githubusercontent.com/senkulabs/infracode-talker/main/go-systemd/install.sh | bash -s -- --hostname=<env>.<app-name>
```

**Manual** (copy `setup.sh` to droplet, then):

```sh
chmod +x setup.sh
./setup.sh --hostname=<env>.<app-name>
```

**With optional components:**

```sh
# With Redis server
./setup.sh --hostname=<env>.<app-name> --with-redis

# With Redis server + Chromium + Lighthouse (for lighthouse worker)
./setup.sh --hostname=<env>.<app-name> --with-redis --with-chromium

# With redis-cli only (Redis runs elsewhere)
./setup.sh --hostname=<env>.<app-name> --with-redis-cli

# With Lightpanda headless browser
./setup.sh --hostname=<env>.<app-name> --with-lightpanda
```

After `setup.sh` completes, it prints `SSH_PRIVATE_KEY` and `SSH_KNOWN_HOSTS` for the `deployer` user. Store these in GitLab CI/CD variables.

> [!IMPORTANT]
> Replace the **public IP address** in `SSH_KNOWN_HOSTS` with your actual hostname. This avoids `Host key verification failed` errors in CI/CD.

4. Write a systemd unit file for your Go binary at `/etc/systemd/system/<service-name>.service`. Example:

```ini
[Unit]
Description=My Go Worker
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/opt/<env>.<app-name>/current/my-worker
WorkingDirectory=/opt/<env>.<app-name>/current
Restart=always
User=deployer

[Install]
WantedBy=multi-user.target
```

Enable and start:

```sh
systemctl enable my-worker
systemctl start my-worker
```

5. Wire up CI/CD to build the Go binary, upload it to `/opt/<env>.<app-name>/current/` via SSH, and restart the systemd service.
