#!/bin/sh
set -eu
log_dir=/var/log/ordyn-postgres
mkdir -p "$log_dir"
chown postgres:2000 "$log_dir"
chmod 2750 "$log_dir"
cleanup() {
    while sleep 60; do
        [ -r "${PGDATA}/current_logfiles" ] || continue
        active=$(awk '$1 == "jsonlog" {print $2}' "${PGDATA}/current_logfiles") || continue
        [ -n "$active" ] || continue
        now=$(date +%s)
        total=0
        for file in "$log_dir"/postgresql-*; do
            case "$file" in *.json|*.log) ;; *) continue ;; esac
            [ -f "$file" ] && [ ! -L "$file" ] || continue
            size=$(stat -c %s "$file") || continue
            total=$((total + size))
        done
        for file in "$log_dir"/postgresql-*; do
            case "$file" in *.json|*.log) ;; *) continue ;; esac
            [ -f "$file" ] && [ ! -L "$file" ] || continue
            # Re-read active metadata before each deletion. Names include seconds and
            # existing files are never truncated/reused by time rotation.
            active=$(awk '$1 == "jsonlog" {print $2}' "${PGDATA}/current_logfiles") || break
            [ -n "$active" ] || break
            [ "$file" != "$active" ] && [ "$file" != "${active%.json}.log" ] || continue
            modified=$(stat -c %Y "$file") || continue
            age=$((now - modified))
            [ "$age" -gt 120 ] || continue
            if [ "$age" -gt "${ORDYN_POSTGRES_LOG_RETENTION_SECONDS:-604800}" ] || [ "$total" -gt "${ORDYN_POSTGRES_LOG_RETENTION_BYTES:-2147483648}" ]; then
                size=$(stat -c %s "$file") || continue
                rm -- "$file" || continue
                total=$((total - size))
            fi
        done
        if [ "$total" -gt "${ORDYN_POSTGRES_LOG_RETENTION_BYTES:-2147483648}" ]; then
            echo 'PostgreSQL log retention budget exceeded by protected active/recent files' >&2
        fi
    done
}
cleanup &
exec /usr/local/bin/docker-entrypoint.sh "$@"
