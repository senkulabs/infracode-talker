# Deploy Laravel with FrankenPHP

## Initial Deployment - Non Container

This is a brief instruction how to setup web server for Laravel framework using:

- [FrankenPHP](https://frankenphp.dev) (modern PHP app server with built-in Caddy + auto HTTPS)
- Postgres
- MariaDB (optional)
- Redis (optional)

> [!WARNING]
> You must run these steps as a root user or user with sudo access.

1. Create [a droplet in Digital Ocean](https://m.do.co/c/303e46500afd) with latest Ubuntu LTS. You may choose droplet with $6 or $12.

| $6                | $12               |
|:------------------|:------------------|
| 1GB vCPU          | 1GB vCPU          |
| 1GB RAM           | 2GB RAM           |
| 25GB SSD          | 50GB SSD          |
| 1000 GiB transfer | 2000 GiB transfer |

2. Once droplet created, create `A record` by using the IP public of droplet into DNS. I'm using Cloudflare as DNS. We will use the `Name` of domain as a hostname in the `deploy.php` file and as the `--hostname` argument in `setup.sh`.

| Type | Name | Content            | Proxy Status | TTL    |
|:-----|:-----|:--------------------|:-------------|:-------|
| A    | web.app | droplet-ip-public   | Proxied      | &nbsp; |

Only one record, kept simple. Using **Proxied**, real droplet IP hidden behind Cloudflare's proxy IPs — visitors and attackers see only Cloudflare's IP, not yours. Bonus: CDN caching, DDoS protection, free SSL termination, no direct exposure of origin server.

Use `web.app` as the `--hostname` argument in `setup.sh` and `deploy.php`.

3. Put `setup.sh` file into root directory in the droplet and make it executable. This executable file do:

- Configure UFW (allow OpenSSH, 80/tcp, 443/tcp, 443/udp)
- Install FrankenPHP (via `https://frankenphp.dev/install.sh`)
- Install Composer
- Install PostgreSQL (default) or MariaDB
- Configure database
- Setup daily DB backup to Cloudflare R2 (optional)
- Install Redis (optional)
- Install ACL
- Create deployer user
- Create SSH Key Pair
- Create site Caddyfile at `/etc/frankenphp/Caddyfile.d/<hostname>.caddyfile`
- Display SSH info

```sh
chmod +x setup.sh
./setup.sh --hostname=gladion.app --db-name=yourdbname --db-user=yourdbuser --db-pass=yourdbpassword
```

> [!TIP]
> If you want to install redis and/or use mariadb: `./setup.sh --hostname=gladion.app --db-name=yourdbname --db-user=yourdbuser --db-pass=yourdbpassword --with-redis --db-engine=mariadb`.

> [!TIP]
> To enable daily DB backups to Cloudflare R2, add `--with-backup` plus the R2 credentials: `./setup.sh --hostname=gladion.app --db-name=yourdbname --db-user=yourdbuser --db-pass=yourdbpassword --with-backup --r2-endpoint=https://xxxx.r2.cloudflarestorage.com --r2-bucket=my-backups --r2-access-key=xxx --r2-secret-key=xxx`. This installs the AWS CLI, drops a backup script at `/usr/local/bin/{mariadb,postgresql}-backup.sh`, and schedules it via cron at 00:00 daily.

After `setup.sh` executed, it will generate `SSH_PRIVATE_KEY` and `SSH_KNOWN_HOSTS` from `deployer` user. These are used for GitLab CI/CD. Store it into GitLab CI/CD variables. So, save it!

> [!IMPORTANT]
> Replace the **public IP address** value in `SSH_KNOWN_HOSTS` with your actual hostname. This will make the deployment smoother by just looking the actual hostname/domain. You must mapped the **public IP address** into DNS record first. Otherwise, you will get error message in CI/CD: `Host key verification failed` in the future.

4. The script generates a site Caddyfile at `/etc/frankenphp/Caddyfile.d/<hostname>.caddyfile` with content:

```
gladion.app {
    root * /var/www/gladion.app/public
    encode zstd br gzip
    php_server
}
```

> [!IMPORTANT]
> The base `/etc/frankenphp/Caddyfile` and the FrankenPHP service (systemd unit) are NOT created by this script. You must set those up manually so that the base Caddyfile imports `Caddyfile.d/*.caddyfile`, e.g.:
>
> ```
> import Caddyfile.d/*.caddyfile
> ```
>
> Then start/reload FrankenPHP (e.g. `systemctl reload frankenphp`) to apply the site config. FrankenPHP/Caddy will automatically obtain a Let's Encrypt TLS certificate for the hostname — no Certbot needed.

5. Prepare a Laravel project. Then, install the [deployer](https://deployer.org) tool and create initial `deploy.php` file.

```sh
composer require deployer/deployer --dev
vendor/bin/dep init -n
```

If you're using Windows (not WSL) + Laragon, then use this command to create initial `deploy.php` file.

```sh
.vendor\bin\dep.bat init -n
```

6. Replace the content of initial `deploy.php` with the specific Laravel deployment setup [deploy.php](../nginx-fpm/deploy.php) (reusable from the nginx-fpm recipe).

> [!IMPORTANT]
> Replace the `laravel.senku.stream` with your actual hostname (e.g. `gladion.app`).

7. Create `.gitlab-ci.yml` file and use the content of [.gitlab-ci.yml](../nginx-fpm/.gitlab-ci.yml.txt). Then hit deploy!
