#!/bin/bash -eux

if [ -z "${BACKUP_FORCE-}" ]; then
  echo This script is not safe to run multiple instances at the same time
  echo Starting through systemctl and forwarding journalctl
  set -eux
  journalctl -fu {{ home.split("/")[-1] }}-backup &
  journalpid="$!"
  systemctl start --wait {{ home.split("/")[-1] }}-backup
  retcode="$?"
  kill $journalpid
  exit $retcode
fi

cd {{ home }}

set -eu
export RESTIC_PASSWORD_FILE={{ home }}/.restic_password
set -x
export RESTIC_REPOSITORY={{ lookup('env', 'RESTIC_REPOSITORY') or home + '/restic' }}

docker-compose up -d postgres
until test -S {{ home }}/postgres/run/.s.PGSQL.5432; do
    sleep 1
done

sleep 3 # ugly wait until db starts up, socket waiting aint enough

backup="{{ restic_backup|default('') }}"

docker-compose exec -T postgres pg_dumpall -U django -c -f /dump/data.dump
docker-compose logs &> log/docker.log || echo "Couldn't get logs from instance"

restic backup $backup docker-compose.yml log postgres/dump/data.dump {{ restic_backup|default('') }}

{% if lookup('env', 'LFTP_DSN') %}
lftp -c 'set ssl:check-hostname false;connect {{ lookup("env", "LFTP_DSN") }}; mkdir -p {{ home.split("/")[-1] }}; mirror -Rve {{ home }}/restic {{ home.split("/")[-1] }}/restic'
{% endif %}

rm -rf {{ home }}/dump/data.dump
