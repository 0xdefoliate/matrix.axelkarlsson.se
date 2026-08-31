#!/usr/bin/env sh

# Ensure we are in $HOME
cd || true

. "$HOME"/config/env

sudo apt update -y && sudo apt upgrade -y
sudo apt install -y --no-install-recommends python3

synapse_postgres_password="$(python3 -c 'import secrets; print(secrets.token_hex(64), end="")')"

## Postgres

sudo apt install -y postgresql libpq5

sudo -u postgres psql <<EOF
create role synapse_user noinherit createrole login password '$synapse_postgres_password';
EOF

sudo -u postgres createdb \
  --encoding=UTF8 --locale=C --template=template0 --owner=synapse_user synapse


## Matrix

sudo apt install -y lsb-release wget apt-transport-https
wget https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
sudo mv matrix-org-archive-keyring.gpg /usr/share/keyrings

echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/matrix-org.list

sudo apt update -y
sudo apt install -y --no-install-recommends matrix-synapse-py3

sed -i 's/%POSTGRES_PLACEHOLDER_PASSWORD/'"$synapse_postgres_password/" "$HOME"/config/synapse/homeserver.yaml

# shellcheck disable=SC2002
cat "$HOME"/config/synapse/homeserver.yaml | \
    sudo tee /etc/matrix-synapse/homeserver.yaml > /dev/null

echo "server_name: axelkarlsson.se" | \
    sudo tee /etc/matrix-synapse/conf.d/server_name.yaml > /dev/null

## Certbot

sudo apt install -y --no-install-recommends python3-dev python3-venv libaugeas-dev gcc

if [ ! -d /opt ]; then
    sudo mkdir /opt
fi

unprivileged_user="$(id -un)"

sudo mkdir /opt/certbot
sudo chown -R "$unprivileged_user" /opt/certbot

python3 -m venv /opt/certbot
/opt/certbot/bin/pip install --upgrade pip
/opt/certbot/bin/pip install certbot
/opt/certbot/bin/pip install certbot-dns-cloudflare

sudo mkdir /var/log/letsencrypt /etc/letsencrypt /var/lib/letsencrypt

sudo chown -R "$unprivileged_user" /var/log/letsencrypt
sudo chown -R "$unprivileged_user" /etc/letsencrypt
sudo chown -R "$unprivileged_user" /var/lib/letsencrypt

sed -i 's/%USER/'"$unprivileged_user/" "$HOME"/config/cron/crontab

# I don't have time to fix this useless use of cat.
# shellcheck disable=SC2002
cat "$HOME"/config/cron/crontab | sudo tee -a /etc/crontab > /dev/null
rm "$HOME"/config/cron/crontab

echo "dns_cloudflare_api_token = $DNS_CLOUDFLARE_TOKEN" > "$HOME"/.cloudflare.ini
chmod 600 "$HOME"/.cloudflare.ini

domains="matrix.axelkarlsson.se axelkarlsson.se"

for domain in $domains; do
    /opt/certbot/bin/certbot certonly                        \
        --dns-cloudflare                                     \
        --dns-cloudflare-credentials "$HOME"/.cloudflare.ini \
        -d "$domain"                                         \
        --non-interactive                                    \
        --agree-tos
done

## Apache

sudo apt install -y --no-install-recommends apache2

sudo a2enmod proxy proxy_http rewrite ssl headers

sudo rm /var/www/html/* # no need to keep the placeholders
sudo rm /etc/apache2/sites-enabled/*.conf

# shellcheck disable=SC2002
cat "$HOME"/config/apache/index.html | \
    sudo tee /var/www/html/index.html > /dev/null

# shellcheck disable=SC2002
cat "$HOME"/config/apache/matrix.conf | \
    sudo tee /etc/apache2/sites-available/matrix.conf > /dev/null

# shellcheck disable=SC2002
cat "$HOME"/config/apache/ports.conf | \
    sudo tee /etc/apache2/ports.conf > /dev/null

sudo a2ensite matrix.conf
sudo apache2ctl configtest

## systemd

for path in "$HOME"/config/systemd/*; do
    service="$(basename "$path")"

    if [ ! -d "/etc/systemd/system/$service" ]; then
        sudo mkdir "/etc/systemd/system/$service"
    fi

    # shellcheck disable=SC2002
    cat "$path"/override.conf | \
        sudo tee /etc/systemd/system/"$service"/override.conf > /dev/null

    # Extract the service's actual name without the trailing ".d".
    service_name="$(python3 -c "print('.'.join('$service'.split('.')[0:-1]), end='')")"

    sudo systemctl daemon-reload
    sudo systemctl restart "$service_name"
done

## Cleanup

### Google Cloud (if hosted there)

# saves a bit of RAM, useful on lower-end machines this server is hosted on.
sudo apt remove -y google-cloud-cli

useless_gcloud_services="google-cloud-ops-agent-fluent-bit google-cloud-ops-agent-opentelemetry-collector google-cloud-ops-agent"

for junk in $useless_gcloud_services; do
    sudo systemctl stop "$junk.service"
    sudo systemctl disable --now "$junk.service"
done

### ---

sudo apt autoremove -y