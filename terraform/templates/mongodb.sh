#!/bin/bash
# MongoDB 8.0 from the official repository, configured as a member of replica set rs0.
# Initialise the set once all members are up: scripts/init-replica-set.sh
set -euo pipefail
apt-get update -y
apt-get install -y gnupg curl
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-8.0.list
apt-get update -y
apt-get install -y mongodb-org
cat > /etc/mongod.conf <<'CONF'
storage:
  dbPath: /var/lib/mongodb
systemLog:
  destination: file
  path: /var/log/mongodb/mongod.log
  logAppend: true
net:
  port: 27017
  bindIp: 0.0.0.0        # network access is restricted by the security group
replication:
  replSetName: rs0
CONF
systemctl enable --now mongod
