#!/bin/sh
# Run this after running directus container
# set directus contaienr name
CONTAINER="directus"
docker exec -u root $CONTAINER chown -R node:node \
    /directus \
    /directus/database \
    /directus/extensions \
    /directus/uploads
