# Infra Code Talker

Infrastructure as a code talker.

Battle-tested deployment recipes for web apps on VPS and cloud. Each recipe includes a `setup.sh` that provisions the server and a `deploy.php` wired to [Deployer](https://deployer.org) for GitLab CI/CD.

## Recipes

| Recipe | Stack | Target |
|:-------|:------|:-------|
| [Laravel + Nginx FPM](./laravel-nginx/README.md) | PHP-FPM, Nginx, PostgreSQL/MariaDB, Redis | DigitalOcean droplet |
| [Laravel + FrankenPHP](./laravel-frankenphp/README.md) | FrankenPHP (Caddy), PostgreSQL/MariaDB, Redis | DigitalOcean droplet |
| [Laravel on Cloud Run](./laravel-cloudrun/README.md) | Docker (Server Side Up), Google Cloud Run | GCP |
| [Go + systemd](./go-systemd/README.md) | Go binary, systemd service | VPS |
