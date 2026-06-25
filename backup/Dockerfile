# Lightweight backup runner: pg_dump (Postgres 16 client) + redis-cli.
# Streams logical SQL dumps of each Postgres DB and a point-in-time Redis RDB.
FROM alpine:3.20

# postgresql16-client -> pg_dump matching the pg16 server; redis -> redis-cli
RUN apk add --no-cache postgresql16-client redis tzdata

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

ENTRYPOINT ["/usr/local/bin/backup.sh"]
