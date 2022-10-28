#!/bin/bash
set -e

# env

if [[ "x$INPUT_GITHUB_TOKEN" == "x" ]]; then
  echo "Missing GITHUB_TOKEN!"
  exit 1
fi

GH_API="https://api.github.com"
GH_HDR_ACCEPT="Accept: application/vnd.github.v3+json"
GH_HDR_AUTH="Authorization: token ${INPUT_GITHUB_TOKEN}"
GH_HDR_CNT="Content-Type: application/json"

resp_action=$(jq --raw-output .action "$GITHUB_EVENT_PATH")
PR_number=$(jq --raw-output .pull_request.number "$GITHUB_EVENT_PATH")
resp_state=$(jq --raw-output .review.state "$GITHUB_EVENT_PATH")

if [[ "x$resp_action" != "xsubmitted" || "x$resp_state" != "xapproved" ]]; then
  echo "Ignoring event ${resp_action} in ${resp_state}"
  exit 0
fi

GH_URL="${GH_API}/repos/${GITHUB_REPOSITORY}/pulls/${PR_number}/reviews?per_page=100"
echo "Getting reviews/approvals from [$GH_URL]"
resp_rev=$(curl -sSL -H "${GH_HDR_ACCEPT}" -H "${GH_HDR_AUTH}" "$GH_URL")

# echo "$resp_rev"
revs=$(echo "$resp_rev" | jq --raw-output '.[] | {state: .state} | @base64')

app_cnt=0

echo "Looping through reviews/approvals"
for rev in $revs;
do
  r="$(echo "$rev" | base64 -d)"
  r_state=$(echo "$r" | jq --raw-output '.state')
  echo "r_state=$r_state"

  if [[ "$r_state" == "APPROVED" ]]; then
    app_cnt=$((app_cnt + 1))
  fi

  if [[ "$app_cnt" -ge "$INPUT_MIN_APPROVALS" ]]; then

    echo "Adding [${INPUT_LABEL}] label to [${PR_number}]"
    curl -sSL -H "${GH_HDR_AUTH}" -H "${GH_HDR_ACCEPT}" -H "${GH_HDR_CNT}" -X POST \
      -d "{\"labels\":[\"${INPUT_LABEL}\"]}" \
      "${GH_API}/repos/${GITHUB_REPOSITORY}/issues/${PR_number}/labels"

    break
  fi
done

echo "Found [$app_cnt] approvals"

