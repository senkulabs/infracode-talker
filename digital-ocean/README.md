# Digital Ocean

## Droplets

> In initial deployment, you must run these steps as a root user.

This is an instruction guide how to setup web server for Laravel framework with using:

- PHP
- Nginx Unit (php-fpm is not necessary)
- Postgres
- Redis

1. Create a $12 droplet with specification like this:

```txt
1GB VCpu
2GB RAM
50GB SSD
2000 GiB transfer
```

2. Put `droplet.sh` file into a droplet and make it executable. Then, run the executable file to run basic software installation like PHP, Nginx Unit, Postgres, and Redis.

```sh
chmod +x setup_laravel_nginx_unit.sh
sudo ./setup_laravel_nginx_unit.sh
```

3. Deploy web app using GitLab CI/CD or GitHub actions. Please see [deploy.php](deploy.php) file.

4. Setup Nginx unit configuration and SSL using Let's encrypt.