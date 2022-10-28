#!/bin/bash
set -e

env

if [[ "x$GITHUB_TOKEN" == "x" ]]; then
  echo "Missing GITHUB_TOKEN!"
  exit 1
fi

GH_API="https://api.github.com"
GH_HDR_ACCEPT="Accept: application/vnd.github.v3+json"
GH_HDR_AUTH="Authorization: token ${GITHUB_TOKEN}"
GH_HDR_CNT="Content-Type: application/json"

resp_action=$(jq --raw-output .action "$GITHUB_EVENT_PATH")
PR_number=$(jq --raw-output .pull_request.number "$GITHUB_EVENT_PATH")
resp_state=$(jq --raw-output .review.state "$GITHUB_EVENT_PATH")

if [ [ "$resp_action" == "submitted" ] && [ "$resp_action" == "approved" ] ]; then
else
  echo "Ignoring event ${resp_action} in ${resp_state}"
  exit 0
fi

resp_rev=$(curl -sSL -H "${GH_HDR_ACCEPT}" -H "${GH_HDR_AUTH}" "${URI}/repos/${GITHUB_REPOSITORY}/pulls/${number}/reviews")
revs=$(echo "$body" | jq --raw-output '.[] | {state: .state} | @base64')

app_cnt=0

for rev in $revs;
do
  r="$(echo "$rev" | base64 -d)"
  r_state=$(echo "$r" | jq --raw-output '.state')

  if [[ "$r_state" == "APPROVED" ]]; then
    app_cnt=$((app_cnt + 1))
  fi

  if [[ "$app_cnt" -ge "$MIN_APPROVALS" ]]; then

    curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" -H "${GH_HDR_CNT}" -X POST \
      -d "{\"labels\":[\"${LABEL}\"]}" \
      "${GH_API}/repos/${GITHUB_REPOSITORY}/issues/${PR_number}/labels"

    break
  fi
done
