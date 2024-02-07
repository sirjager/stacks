#!/bin/bash

DOMAIN_NAME="mydomain.com"

MAIL_USERNAME="username"
MAIL_PASSWORD="password"

docker run --rm \
	-e MAIL_USER="$MAIL_USERNAME@$DOMAIN_NAME" \
	-e MAIL_PASS="$MAIL_PASSWORD" \
	-it mailserver/docker-mailserver /bin/sh -c 'echo "$MAIL_USER|$(doveadm pw -s SHA512-CRYPT -u $MAIL_USER -p $MAIL_PASS)"' \
	>>./data/config/postfix-accounts.cf
