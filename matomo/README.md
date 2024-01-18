## Backup Matomo Database

docker exec -it matomo-db bash
time mysqldump --extended-insert --no-autocommit --quick --single-transaction matomo -u matomo -p > ./matomo.sql

## Restore Matomo Database

docker exec -it matomo-db bash
time mysql matomo-db -u matomo -p < matomo.sql
