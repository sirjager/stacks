#!/bin/bash

mkdir ./data/logs -p
mkdir ./data/data -p
mkdir ./data/state -p
mkdir ./data/config -p

sudo chown "$USER":"$USER" ./data -R

MAIL_SERVER_HOSTNAME="mail.mydomain.com"
DOMAIN_NAME="mydomain.com"

# run the mailserver container
docker run -d --name=mailserver \
	--hostname="$MAIL_SERVER_HOSTNAME" \
	--domainname="$DOMAIN_NAME" \
	-p 25:25 -p 143:143 -p 587:587 -p 993:993 \
	-e ENABLE_SPAMASSASSIN=1 \
	-e SPAMASSASSIN_SPAM_TO_INBOX=1 \
	-e ENABLE_CLAMAV=1 \
	-e ENABLE_POSTGREY=1 \
	-e ENABLE_FAIL2BAN=0 \
	-e ENABLE_SASLAUTHD=0 \
	-e ONE_DIR=1 \
	-v ./data/data/:/var/mail/ \
	-v ./data/state/:/var/mail-state/ \
	-v ./data/logs/:/var/log/mail/ \
	-v ./data/config/:/tmp/docker-mailserver/ \
	--restart=unless-stopped \
	mailserver/docker-mailserver
