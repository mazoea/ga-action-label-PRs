#!/bin/bash
set -euo pipefail

# Inputs are delivered to a Docker action as INPUT_<NAME> env vars.
# We never read them from $1/$2/$3 (that would mean exposing the token in
# the container's argv, visible via /proc/1/cmdline and `docker inspect`).
INPUT_GITHUB_TOKEN="${INPUT_GITHUB_TOKEN:-}"
INPUT_MIN_APPROVALS="${INPUT_MIN_APPROVALS:-}"
INPUT_LABEL="${INPUT_LABEL:-}"

if [[ -z "$INPUT_GITHUB_TOKEN" ]]; then
  echo "Missing GITHUB_TOKEN!" >&2
  exit 1
fi

if [[ -z "$INPUT_LABEL" ]]; then
  echo "Missing LABEL!" >&2
  exit 1
fi

if ! [[ "$INPUT_MIN_APPROVALS" =~ ^[0-9]+$ ]] || [[ "$INPUT_MIN_APPROVALS" -lt 1 ]]; then
  echo "Invalid MIN_APPROVALS: must be a positive integer (got: '$INPUT_MIN_APPROVALS')" >&2
  exit 1
fi

# Defense in depth: the script only makes sense for pull_request_review
# events. If a workflow misconfigures the trigger, bail before touching
# the API.
if [[ "${GITHUB_EVENT_NAME:-}" != "pull_request_review" ]]; then
  echo "Ignoring event '${GITHUB_EVENT_NAME:-}': this action expects pull_request_review."
  exit 0
fi

GH_API="${GITHUB_API_URL:-https://api.github.com}"
GH_HDR_ACCEPT="Accept: application/vnd.github.v3+json"
GH_HDR_AUTH="Authorization: token ${INPUT_GITHUB_TOKEN}"
GH_HDR_CNT="Content-Type: application/json"

resp_action=$(jq --raw-output .action "$GITHUB_EVENT_PATH")
PR_number=$(jq --raw-output .pull_request.number "$GITHUB_EVENT_PATH")
resp_state=$(jq --raw-output .review.state "$GITHUB_EVENT_PATH")

if [[ "$resp_action" != "submitted" || "$resp_state" != "approved" ]]; then
  echo "Ignoring event ${resp_action} in ${resp_state}"
  exit 0
fi

GH_URL="${GH_API}/repos/${GITHUB_REPOSITORY}/pulls/${PR_number}/reviews?per_page=100"
echo "Getting reviews/approvals from [$GH_URL]"
resp_rev=$(curl --fail-with-body -sSL -H "${GH_HDR_ACCEPT}" -H "${GH_HDR_AUTH}" "$GH_URL")

# Count APPROVED reviews in one shot. Old code base64-encoded each item
# and looped a shell `for` over the encoded strings, which was both
# fragile (word-splitting) and misleading (the printed counter capped at
# the threshold because the labeling block lived inside the loop and
# `break`-ed early).
app_cnt=$(echo "$resp_rev" | jq '[.[] | select(.state == "APPROVED")] | length')
echo "Found [$app_cnt] APPROVED reviews"

if [[ "$app_cnt" -lt "$INPUT_MIN_APPROVALS" ]]; then
  echo "Below threshold ($INPUT_MIN_APPROVALS); not labeling."
  exit 0
fi

echo "Adding [${INPUT_LABEL}] label to PR [${PR_number}]"
# Build the JSON via jq so a label name containing `"` or `\` can't break
# the body or smuggle a second label.
PAYLOAD=$(jq -nc --arg label "$INPUT_LABEL" '{labels: [$label]}')
http_code=$(curl -sS -o /tmp/label_resp -w '%{http_code}' \
  -H "${GH_HDR_AUTH}" -H "${GH_HDR_ACCEPT}" -H "${GH_HDR_CNT}" \
  -X POST \
  -d "$PAYLOAD" \
  "${GH_API}/repos/${GITHUB_REPOSITORY}/issues/${PR_number}/labels")

if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
  echo "Failed to apply label, HTTP $http_code:" >&2
  cat /tmp/label_resp >&2 || true
  exit 1
fi

echo "Label applied."
