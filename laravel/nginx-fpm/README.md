# Deploy Laravel with Nginx FPM

## Initial Deployment - Non Container

This is a brief instruction how to setup web server for Laravel framework using:

- PHP (include php-fpm)
- Nginx
- Postgres
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

2. Once droplet created, create `A record` by using the IP public of droplet into DNS. I'm using Cloudflare as DNS. We will use the `Name` of domain as a hostname in the `deploy.php` file.

| Type | Name                    | Content             | Proxy Status | TTL      |
|:-----|:------------------------|:--------------------|:-------------|:---------|
| A    | laravel.senku.stream    | droplet-ip-public   | DNS only     | &nbsp;   |

3. Put `setup.sh` file into root directory in the droplet and make it executable. This executable file do:

- Install PHP and PHP extensions
- Install Nginx
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
./setup.sh --db-name=yourdbname --db-user=yourdbuser --db-pass=yourdbpassword
```

> [!TIP]
> If you want to install redis and/or mariadb, it will be like this: `./setup.sh --db-name=yourdbname --db-user=yourdbuser --db-pass=yourdbpassword --with-redis --db-engine=mariadb`.

After `setup.sh` executed, it will generate `SSH_PRIVATE_KEY` and `SSH_KNOWN_HOSTS` from `deployer` user. These are used for GitLab CI/CD. Store it into GitLab CI/CD variables. So, save it!

> [!IMPORTANT] 
> Replace the **public IP address** value in `SSH_KNOWN_HOSTS` with your actual hostname. This will make the deployment smoother by just looking the actual hostname/domain. You must mapped the **public IP address** into DNS record first. Otherwise, you will get error message in CI/CD: `Host key verification failed` in the future.

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

> [!IMPORTANT] 
> Replace the `laravel.senku.stream` with your actual hostname.

6. Create `.gitlab-ci.yml` file and use the content of [.gitlab-ci.yml](.gitlab-ci.yml.txt) in this repository. Then hit deploy!
