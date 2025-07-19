--- Semi Automated ---
- install php and extensions for Laravel framework
    - `sudo apt install php-bcmath php-cli php-curl php-gd php-mbstring php-mysql php-pgsql php-redis php-sqlite3 php-xml php-zip unzip -y`
- install nginx unit
    - Download & save Nginx signing key:
        `curl --output /usr/share/keyrings/nginx-keyring.gpg  \
      https://unit.nginx.org/keys/nginx-keyring.gpg`
    - Configure unit's repository by create the unit.list file in `/etc/apt/sources.list.d/unit.list`:
        `deb [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/ubuntu/ noble unit
deb-src [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/ubuntu/ noble unit`
    - `sudo apt update && sudo apt install unit -y`
    - `sudo apt install unit-dev unit-php -y`
    - `sudo systemctl restart unit`
    - Check if nginx unit has running with command `sudo systemctl status unit`
- install composer
    - `curl -sLS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/bin/ --filename=composer`
- create `/var/www` directory
    - `sudo mkdir -p /var/www`
- install certbot for https protocol
    - install system dependencies: `sudo apt update && sudo apt install python3 python3-venv libaugeas-dev -y`
    - setup python virtual environment: `sudo python3 -m venv /opt/certbot/ && sudo /opt/certbot/bin/pip install --upgrade pip`
    - install certbot: `sudo /opt/certbot/bin/pip install certbot`
    - prepare certbot command by symlink: `sudo ln -s /opt/certbot/bin/certbot /usr/bin/certbot`

--- Unknown ---
- create Laravel project with command `sudo composer create-project laravel/laravel html` inside `/var/www`
- change owner directory and files inside `/var/www/html` into unit:unit with `chown -R unit:unit /var/www/html`
- create Laravel configuration for Nginx Unit in /tmp directory
    filename: unit-html-http.json
- update the Laravel configuration for Nginx Unit with command below:
    `curl -X PUT --data-binary @/tmp/unit-html-http.json --unix-socket \
       /path/to/control.unit.sock http://localhost/config/`
- register the public ip into the DNS so access it via domain.
- create `.well-known/acme-challenge` directory inside the `/var/www/html` if you want to access the site into https.
    - `mkdir -p /var/www/html/.well-known/acme-challenge`
    - `chown -R unit:unit /var/www/html/.well-known/acme-challenge`
- create Laravel configuration for Nginx Unit with https protocol
    filename: unit-html-https.json
- update Laravel configuration for Nginx Unit with command below:
    `curl -X PUT --data-binary @/tmp/unit-html-https.json --unix-socket \
       /var/run/control.unit.sock http://localhost/config/`
- run certbot in `--webroot` flag: `certbot certonly --webroot -w /var/www/html -d laravel.senku.stream --non-interactive --agree-tos -m halo@kresna.me`.
- Create bundle certificate by combine fullchain and private key into one bundle.file in /tmp directory:
`cat /etc/letsencrypt/live/laravel.senku.stream/fullchain.pem /etc/letsencrypt/live/laravel.senku.stream/privkey.pem > /tmp/bundle.pem`
- Apply bundle certificate in Nginx Unit:
    `curl -X PUT --data-binary @/tmp/bundle.pem \
    --unix-socket /var/run/control.unit.sock \
    http://localhost/certificates/bundle`
    Response: {
	"success": "Certificate chain uploaded."
}
`curl -X PUT --data-binary @/tmp/unit-https.json --unix-socket \
       /var/run/control.unit.sock http://localhost/config/`