#!/usr/bin/env bash
# Sauvegarde PostgreSQL (Linux). Cron : 0 2 * * * /chemin/focusely/deploy/backup.sh
set -euo pipefail
OUT="${1:-$(dirname "$0")/../backups}"; KEEP="${KEEP:-14}"
mkdir -p "$OUT"
NAME=$(docker ps --format '{{.Names}} {{.Image}}' | grep -i postgres | head -n1 | cut -d' ' -f1)
[ -n "$NAME" ] || { echo "Aucun conteneur PostgreSQL" >&2; exit 1; }
USER_=$(docker exec "$NAME" printenv POSTGRES_USER || echo postgres)
DB=$(docker exec "$NAME" printenv POSTGRES_DB || echo "$USER_")
FILE="$OUT/focusely_$(date +%Y%m%d_%H%M%S).dump"
docker exec "$NAME" pg_dump -U "$USER_" -d "$DB" -Fc -f /tmp/focusely.dump
docker cp "$NAME:/tmp/focusely.dump" "$FILE"
docker exec "$NAME" rm -f /tmp/focusely.dump
echo "Sauvegarde : $FILE"
ls -1t "$OUT"/focusely_*.dump | tail -n +$((KEEP + 1)) | xargs -r rm -f