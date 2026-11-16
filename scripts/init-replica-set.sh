#!/usr/bin/env bash
# Initialise the MongoDB replica set once all three members are running.
# Runs mongosh on the first member through SSM Run Command, so no SSH or VPN is needed.
#
#   ./scripts/init-replica-set.sh            # reads instance IDs and IPs from terraform output
set -euo pipefail
cd "$(dirname "$0")/../terraform"

mapfile -t IDS < <(terraform output -json db_instance_ids | jq -r '.[]')
mapfile -t IPS < <(terraform output -json db_private_ips | jq -r '.[]')
[[ ${#IPS[@]} -eq 3 ]] || { echo "expected 3 members, got ${#IPS[@]}" >&2; exit 1; }

MEMBERS=$(for i in 0 1 2; do printf '{_id:%d,host:"%s:27017"},' "$i" "${IPS[$i]}"; done)
JS="try { rs.status().ok } catch (e) { rs.initiate({_id:'rs0',members:[${MEMBERS%,}]}) }"

CMD_ID=$(aws ssm send-command \
  --instance-ids "${IDS[0]}" \
  --document-name AWS-RunShellScript \
  --comment "init rs0" \
  --parameters "commands=[\"mongosh --quiet --eval \\\"${JS}\\\"\"]" \
  --query Command.CommandId --output text)

aws ssm wait command-executed --command-id "$CMD_ID" --instance-id "${IDS[0]}"
aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "${IDS[0]}" \
  --query '{status:Status,output:StandardOutputContent,error:StandardErrorContent}'
