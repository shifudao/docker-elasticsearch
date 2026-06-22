#!/bin/sh
set -e

# Add elasticsearch as command if needed
case "$1" in
  -*) set -- elasticsearch "$@" ;;
esac

# Drop root privileges if we are running elasticsearch
# allow the container to be started with `--user`
if [ "$1" = 'elasticsearch' ] && [ "$(id -u)" = '0' ]; then
  # Change the ownership of /usr/share/elasticsearch/data to elasticsearch
  chown -R elasticsearch:elasticsearch /usr/share/elasticsearch/data

  set -- su-exec elasticsearch "$@"
fi

# As argument is not related to elasticsearch,
# then assume that user wants to run his own process,
# for example a `sh` shell to explore this image
exec "$@"
