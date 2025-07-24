# Digital Ocean

## Initial Deployment - Non Container

This is a brief instruction how to setup web server for Laravel framework using:

- PHP
- Nginx Unit (php-fpm is not necessary)
- Postgres
- Redis

> You must run these steps as a root user or user with sudo access.

1. Create [a droplet in Digital Ocean](https://m.do.co/c/303e46500afd) with latest Ubuntu LTS. You may choose droplet with $6 or $12.

| $6                | $12               |
|:------------------|:------------------|
| 1GB vCPU          | 1GB vCPU          |
| 1GB RAM           | 2GB RAM           |
| 25GB SSD          | 50GB SSD          |
| 1000 GiB transfer | 2000 GiB transfer |

2. Once droplet created, create `A record` by using the IP public of droplet into DNS. I'm using Cloudflare as DNS. We will use the `Name` of domain as a hostname in the `deploy.php` file.

| Type | Name                    | Content             | Proxy Status | TTL      |
|:-----|:------------------------|:--------------------|:-------------|:---------|
| A    | laravel.senku.stream    | <droplet-ip-public> | DNS only     | New Cell |

3. Put `setup.sh` file into a `/tmp` directory in the droplet and make it executable. This executable file do:

- Install PHP and PHP extensions
- Install Nginx unit
- Install Composer
- Create `/var/www` directory
- Install PostgreSQL
- Configure PostgreSQL database
- Install Redis
- Install Certbot
- Install ACL
- Create deployer user
- Configure deployer sudo
- Create SSH key pair
- Display SSH info

```sh
chmod +x setup.sh
sudo ./setup.sh
```

4. Prepare a Laravel project. Then, install the [deployer](https://deployer.org) tool and create initial `deploy.php` file.

```sh
composer require deployer/deployer --dev
vendor/bin/dep init -n
```

If you're using Windows (not WSL) + Laragon, then use this command to create initial `deploy.php` file.

```sh
.vendor\bin\dep.bat init -n
```

5. Replace the content of initial `deploy.php` with the specific Laravel deployment setup [deploy.php](deploy.php) in this repository.

6. Create `.gitlab-ci.yml` file and use the content of [.gitlab-ci.yml](.gitlab-ci.yml.txt) in this repository. Then hit deploy!

7. Create `unit-http.json` file in `/tmp`directory in the droplet. Then, use the content of [unit-http.json](unit-http.json) from this repository. The file contains the routes direct to Laravel application and `.well-known/acme-challenge` for create Let's Encrypt Certificate.

8. Update Nginx unit configuration with command below and you will see the response `Reconfiguration done.` if everything is success.

```sh
curl -X PUT --data-binary @/tmp/unit-http.json --unix-socket /var/run/control.unit.sock http://localhost/config/
```

Now, you can access the Laravel project with domain [laravel.senku.stream](laravel.senku.stream). But, currently in HTTP protocol. We will turn it into HTTPS protocol in the next step.

9. Each time you deploy using Deployer, Deployer will create a folder inside `releases` folder. For example: in initial deployment it create folder `1` in `releases` then it create symbolic link with `current` folder. If any git push happen then Deployer will create another folder called `2` in releases folder then move the symbolic link from folder `1` to `2` into the `current` folder. Because we use this approach then we need to tell Nginx Unit to reload the service that belongs to this app. In [deploy.php](deploy.php) file, we create task called `unit:reload`. This tell the Nginx Unit to reload the `applications/laravel` that we defined in [unit-http.json](unit-http.json) file.

10. Create Let's Encrypt certificate.

```sh
certbot certonly --webroot -w /var/www/html -d laravel.senku.stream --non-interactive --agree-tos -m halo@kresna.me
```

> Note: Replace the laravel.senku.stream with your actual domain.

11. Create a certificate bundle with name `bundle` into `/tmp` directory. 

```sh
cat /etc/letsencrypt/live/laravel.senku.stream/fullchain.pem /etc/letsencrypt/live/laravel.senku.stream/privkey.pem > /tmp/bundle.pem
```

11. Create `unit-https.json` file in `/tmp`directory in the droplet. Then, use the content of [unit-https.json](unit-https.json) from this repository.

12. Update Nginx unit configuration with command below and you will see the response `Reconfiguration done.` if everything is success.

```sh
curl -X PUT --data-binary @/tmp/unit-https.json --unix-socket /var/run/control.unit.sock http://localhost/config/
```

Now, everytime you access the `laravel.senku.stream`, it will redirect to HTTPS.