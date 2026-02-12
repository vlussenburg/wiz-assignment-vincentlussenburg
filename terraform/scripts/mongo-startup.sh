#!/bin/bash
set -euo pipefail

# ---------- Install MongoDB 6.0 (intentionally outdated, EOL Aug 2025) ----------

apt-get update
apt-get install -y gnupg curl

curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-6.0.list

apt-get update
apt-get install -y mongodb-org

# ---------- Configure MongoDB ----------

cat > /etc/mongod.conf <<'MONGOCFG'
storage:
  dbPath: /var/lib/mongodb

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

net:
  port: 27017
  bindIp: 0.0.0.0

security:
  authorization: enabled
MONGOCFG

# Start MongoDB without auth first to create users
sed -i 's/authorization: enabled/authorization: disabled/' /etc/mongod.conf
systemctl enable mongod
systemctl restart mongod

# Wait for MongoDB to be ready
for i in $(seq 1 30); do
  if mongosh --quiet --eval "db.runCommand({ping:1})" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# ---------- Create Users ----------

mongosh --quiet <<SETUPJS
use admin
db.createUser({
  user: "${mongo_admin_user}",
  pwd: "${mongo_admin_password}",
  roles: [{ role: "root", db: "admin" }]
});

use bucketlist
db.createUser({
  user: "${mongo_app_user}",
  pwd: "${mongo_app_password}",
  roles: [{ role: "readWrite", db: "bucketlist" }]
});
SETUPJS

# Re-enable auth and restart
sed -i 's/authorization: disabled/authorization: enabled/' /etc/mongod.conf
systemctl restart mongod

# ---------- Daily Backup Cron ----------

cat > /usr/local/bin/mongo-backup.sh <<'BACKUP'
#!/bin/bash
set -euo pipefail
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DUMP_DIR="/tmp/mongodump-$TIMESTAMP"
mongodump \
  --host=localhost --port=27017 \
  --username='${mongo_admin_user}' --password='${mongo_admin_password}' \
  --authenticationDatabase=admin \
  --out="$DUMP_DIR"
tar czf "/tmp/backup-$TIMESTAMP.tar.gz" -C "$DUMP_DIR" .
gsutil cp "/tmp/backup-$TIMESTAMP.tar.gz" "gs://${backup_bucket}/backup-$TIMESTAMP.tar.gz"
rm -rf "$DUMP_DIR" "/tmp/backup-$TIMESTAMP.tar.gz"
BACKUP

chmod +x /usr/local/bin/mongo-backup.sh

# Run daily at 2 AM
echo "0 2 * * * root /usr/local/bin/mongo-backup.sh" > /etc/cron.d/mongo-backup
chmod 0644 /etc/cron.d/mongo-backup

echo "MongoDB startup script completed successfully."
