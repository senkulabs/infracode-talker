# Digital Ocean

## Initial Deployment - Non Container

This is a brief instruction how to setup web server for Laravel framework with using:

- PHP
- Nginx Unit (php-fpm is not necessary)
- Postgres
- Redis

> You must run these steps as a root user or user with sudo access.

1. Create a $12 droplet with specification like this:

```txt
1GB VCpu
2GB RAM
50GB SSD
2000 GiB transfer
```

2. After droplet created, then create `A record` by using the IP public of droplet into DNS. I'm using Cloudflare as DNS. We will use the `Name` of domain as a hostname in the `deploy.php` file.

| Type | Name                    | Content             | Proxy Status | TTL      |
|:-----|:------------------------|:--------------------|:-------------|:---------|
| A    | laravelapp.senku.stream | <droplet-ip-public> | DNS only     | New Cell |

3. Put `initial-setup.sh` file into a `/tmp` directory in the droplet and make it executable. Then, run the executable file to run basic software installation like PHP, Nginx Unit, Postgres, Redis, create deployer user, and setup SSH key pair.

```sh
chmod +x initial-setup.sh
sudo ./initial-setup.sh
```

4. Copy SSH private key from `deployer` user for CI/CD. Save the private key as `SSH_PRIVATE_KEY`.

```sh
# switch to deployer user with command
# sudo -u deployer -s
cd /home/deployer/.ssh
cat id_ed25519
```

After run the `cat` command, copy all the blocks of SSH private key.

```
-----BEGIN OPENSSH PRIVATE KEY-----
long_text_goes_here
-----END OPENSSH PRIVATE KEY-----
```

5. Copy SSH known hosts value for CI/CD. Save it as `SSH_KNOWN_HOSTS`. This used for to prevent man in the middle attack.

```sh
ssh-keyscan <ip-public-droplet> | grep "ssh-ed25519"
```

6. Prepare a Laravel project. Then, install the [deployer](https://deployer.org) tool and create initial `deploy.php` file.

```sh
composer require deployer/deployer --dev
vendor/bin/dep init -n
```

If you're using Windows (not WSL) + Laragon, then use this command to create initial `deploy.php` file.

```sh
.vendor\bin\dep.bat init -n
```

6. Replace the content of initial `deploy.php` with the specific Laravel deployment setup [deploy.php](deploy.php) in this repository.

7. Create `.gitlab-ci.yml` file and use the content of [.gitlab-ci.yml](.gitlab-ci.yml.txt) in this repository.

8. Create `unit-http.json` file in `/tmp`directory in the droplet. Then, use the content of [unit-http.json](unit-http.json) from this repository.

9. Update Nginx unit configuration with command below and you will see the response `reconfiguration: done`.

```sh
curl -X PUT --data-binary @/tmp/unit-http.json --unix-socket /var/run/control.unit.sock http://localhost/config/
```