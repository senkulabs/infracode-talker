# Digital Ocean

## Initial Deployment - Non Container

This is a brief instruction how to setup web server for Laravel framework using:

- PHP
- Nginx Unit (php-fpm is not necessary)
- Postgres
- Redis

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

After `setup.sh` execute then it will generate `SSH_PRIVATE_KEY` and `SSH_KNOWN_HOSTS`. These are used for GitLab CI/CD. Store it into GitLab CI/CD variables.

> [!WARNING]
> You may modify the value of `SSH_KNOWN_HOSTS` from public IP address into domain. Otherwise, the deployment process will be error.

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

Each time you deploy using Deployer, Deployer will create a folder inside `releases` folder. For example: in initial deployment it create folder `1` in `releases` then it create symbolic link with `current` folder. If any git push happen then Deployer will create another folder called `2` in releases folder then move the symbolic link from folder `1` to `2` into the `current` folder. Because we use this approach then we need to tell Nginx Unit to reload the service that belongs to this app. In [deploy.php](deploy.php) file, we create task called `unit:reload`. This tell the Nginx Unit to reload the `applications/laravel` that we defined in [setup.sh](setup.sh) file.

Now, you can access the Laravel project with domain [laravel.senku.stream](laravel.senku.stream). But, currently in HTTP protocol. We will turn it into HTTPS protocol in the next step.

7. Create Let's Encrypt certificate as a deployer user.

```sh
certbot certonly --webroot -w /var/www/html -d laravel.senku.stream --non-interactive --agree-tos -m halo@kresna.me
```

> [!TIP] 
> Replace the laravel.senku.stream with your actual domain.

8. Create a certificate bundle with name `bundle` into `/home/deployer` directory. 

```sh
cat /etc/letsencrypt/live/laravel.senku.stream/fullchain.pem /etc/letsencrypt/live/laravel.senku.stream/privkey.pem > /home/deployer/bundle.pem
```

9. Update Nginx unit configuration with command below and you will see the response `Reconfiguration done.` if everything is success.

```sh
curl -X PUT --data-binary @unit-https.json --unix-socket /var/run/control.unit.sock http://localhost/config/
```

Now, everytime you access the `laravel.senku.stream`, it will redirect to HTTPS.