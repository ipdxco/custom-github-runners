#!/bin/bash

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI could not be found. Please install it first."
    exit 1
fi

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI could not be found. Please install it first."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install it first."
    exit 1
fi

# Check the number of arguments
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <required:runner:name> <required:organization:name> <optional:repository:name>"
    exit 1
fi

RUNNER_NAME=$1
REPOSITORY_OWNER=$2
REPOSITORY_NAME=$3

PARAMETER_RUNNER_MATCHER_CONFIG_PATH="/github-action-runners/multi/webhook/runner-matcher-config"
PARAMETER_RUNNER_MATCHER_CONFIG="$(aws ssm get-parameters --names $PARAMETER_RUNNER_MATCHER_CONFIG_PATH --query "Parameters[0].Value" --output text)"

echo "Retrieved RUNNER_MATCHER_CONFIG from AWS SSM ($PARAMETER_RUNNER_MATCHER_CONFIG)"

QUEUE_URL="$(jq -r 'map(select(.key == "'"$RUNNER_NAME"'")) | first | .id' <<< "$PARAMETER_RUNNER_MATCHER_CONFIG")"

if [ "$QUEUE_URL" == "null" ]; then
    echo "No queue found for the runner name: $RUNNER_NAME"
    exit 1
fi

echo "Retrieved QUEUE_URL from AWS SSM ($QUEUE_URL)"

INSTALLATIONS="$(gh api "/orgs/$REPOSITORY_OWNER/installations" --paginate)"

echo "Retrieved INSTALLATIONS from GitHub API ($INSTALLATIONS)"

# INSTALLATION_ID="$(jq -r '.installations | map(select(.app_id == '"$TF_VAR_github_app_id"')) | first | .id' <<< "$INSTALLATIONS")"
INSTALLATION_ID="$(jq -r '.installations | map(select(.app_slug | startswith("custom-gh-runners-by-ipdx-co"))) | first | .id' <<< "$INSTALLATIONS")"

if [ "$INSTALLATION_ID" == "null" ]; then
    echo "No installation found for the repository owner: $REPOSITORY_OWNER"
    exit 1
fi

echo "Retrieved INSTALLATION_ID from GitHub API ($INSTALLATION_ID)"

JOB_ID="$RANDOM"
EVENT_BODY='{
  "repositoryName": "'"$REPOSITORY_NAME"'",
  "repositoryOwner": "'"$REPOSITORY_OWNER"'",
  "eventType": "workflow_job",
  "installationId": "'"$INSTALLATION_ID"'",
  "id": "'"$JOB_ID"'"
}'

# Send the message to the SQS queue
RESPONSE="$(aws sqs send-message --queue-url $QUEUE_URL --message-body "$EVENT_BODY" --message-group-id $JOB_ID)"

echo "Sent message to the queue ($RESPONSE)"

if [ "$RESPONSE" == "" ]; then
    echo "Failed to schedule the runner ($RUNNER_NAME)"
    exit 1
else
    echo "Successfully scheduled the runner ($RUNNER_NAME)"
fi
