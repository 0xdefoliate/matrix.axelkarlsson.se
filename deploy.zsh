#!/usr/bin/env zsh

function main {
    local cwd
    cwd="$(dirname "${0:A}")"

    if [[ "$1" == "new" ]]; then
        if [[ ! -f "$cwd"/.env ]]; then
            printf "Missing .env file in project root!\n"
            printf "You need to enter the following key-value pairs in .env:\n"
            printf "  * REMOTE_USER -- an unprivileged user which can perform sudo commands without a password\n"
            printf "  * REMOTE_HOST -- the hostname you want to install the Matrix server to\n"
            printf "  * DNS_CLOUDFLARE_TOKEN -- a fine-grained Cloudflare token which is allowed to write to DNS\n"
            exit 1
        fi

        source "$cwd"/.env

        ssh "$REMOTE_USER@$REMOTE_HOST" 'sudo apt install -y --no-install-recommends rsync'

        rsync -azv "$cwd"/cron "$cwd"/apache "$cwd"/synapse "$cwd"/systemd \
            "$REMOTE_USER@$REMOTE_HOST:/home/$REMOTE_USER/config"

        ssh "$REMOTE_USER@$REMOTE_HOST" 'echo "'"$(cat "$cwd"/.env)"'" > $HOME/config/env'
        ssh "$REMOTE_USER@$REMOTE_HOST" < "$cwd"/scripts/setup.sh

        exit
    fi
}

main "$@"