# create main working directories

mkdir ~/docker/mailserver/{data,state,logs,config} -p

# set owner of working directories

sudo chown "$USER":"$USER" ~/docker -R

# run the mailserver container

docker run -d --name=mailserver --hostname="$HOSTNAME" --domainname="docker.local" -p 25:25 -p 143:143 -p 587:587 -p 993:993 -e ENABLE_SPAMASSASSIN=1 -e SPAMASSASSIN_SPAM_TO_INBOX=1 -e ENABLE_CLAMAV=1 -e ENABLE_POSTGREY=1 -e ENABLE_FAIL2BAN=0 -e ENABLE_SASLAUTHD=0 -e ONE_DIR=1 -e TZ=America/New_York -v ~/docker/mailserver/data/:/var/mail/ -v ~/docker/mailserver/state/:/var/mail-state/ -v ~/docker/mailserver/logs/:/var/log/mail/ -v ~/docker/mailserver/config/:/tmp/docker-mailserver/ --restart=unless-stopped mailserver/docker-mailserver

# create a user/inbox

docker run --rm -e MAIL_USER=<i12bretro@docker.local> -e MAIL_PASS=supersecret -it mailserver/docker-mailserver /bin/sh -c 'echo "$MAIL_USER|$(doveadm pw -s SHA512-CRYPT -u $MAIL_USER -p $MAIL_PASS)"' >> ~/docker/mailserver/config/postfix-accounts.cf
