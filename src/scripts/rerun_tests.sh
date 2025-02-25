#!/bin/bash

cleanup_env_var() {
  echo "Delete env var : $DELETE_ENV_VAR"
  echo "Cleanup env var : $CLEANUP_ENV_VAR"
  # Check if the cleanup flag is set to true
  if [[ "$DELETE_ENV_VAR" == "1" || "$CLEANUP_ENV_VAR" == "1" ]]; then
    echo "Deleting the project environment variable: $env_var"
    curl -X DELETE "https://circleci.com/api/v2/project/${PROJECT_SLUG}/envvar/${env_var}" \
        -H "Circle-Token: ${CIRCLECI_TOKEN}" \
        -H "Content-Type: application/json"
  fi
}

set_env_var() {
  if [[ -z "$CLEANUP_ENV_VAR" || "$CLEANUP_ENV_VAR" != "true" ]]; then
    echo "Setting BS_env_vars in BASH_ENV"
    decoded_json=$(echo "$env_var_value" | base64 --decode 2>/dev/null)
    # Check if the decoded value is valid JSON
    if echo "$decoded_json" | jq empty 2>/dev/null; then
        echo "Valid JSON detected."

        # Print formatted JSON for debugging
        echo "$decoded_json" | jq .

        # Export JSON to environment (compact format)
        echo "export BS_ENV_VARS='$(echo "$decoded_json" | jq -c .)'" >> "$BASH_ENV"
    else
        echo "Invalid JSON detected. Exiting."
        exit 0
    fi
  fi
}

sanitizeToAlphanumericKey() {
  local key="$1"
  echo "${key//[^a-zA-Z0-9]/_}"
}

sanitizeAndLimit() {
  local key="$1"
  local sanitized_key
  sanitized_key=$(sanitizeToAlphanumericKey "$key")
  echo "${sanitized_key:0:50}"
}

buildEnvironmentVariable() {
  local envKey="$1"
  shift
  local values=("$@")

  sanitized_values=()
  for value in "${values[@]}"; do
    sanitized_values+=("$(sanitizeAndLimit "$value")")
  done

  echo "$envKey"_"$(IFS=_; echo "${sanitized_values[*]}")"
}

# Check whether CircleCI token is present
if [[ -z "$CIRCLECI_TOKEN" ]]; then
  echo "CircleCI token not present in environment variables. Setting no tests to rerun."
  exit 0
fi

# Fetch workflow details
WORKFLOW_RESPONSE=$(curl -s -H "Circle-Token: ${CIRCLECI_TOKEN}" \
                        "https://circleci.com/api/v2/workflow/${CIRCLE_WORKFLOW_ID}")

if echo "$WORKFLOW_RESPONSE" | jq empty 2>/dev/null; then
  # Extract workflow details only if JSON is valid
  WORKFLOW_NAME=$(echo "$WORKFLOW_RESPONSE" | jq -r '.name // empty')
  PROJECT_SLUG=$(echo "$WORKFLOW_RESPONSE" | jq -r '.project_slug // empty')
  WORKFLOW_TAG=$(echo "$WORKFLOW_RESPONSE" | jq -r '.tag // empty')

  if [[ -z "$WORKFLOW_NAME" || -z "$PROJECT_SLUG" ]]; then
    echo "Error: Missing workflow name or project slug in API response.Setting no tests to rerun"
    exit 0
  fi
  if [[ "$WORKFLOW_TAG" == "rerun-workflow-from-beginning" ]]; then
    echo "Workflow is a rerun from the beginning. Proceeding with env var operations..."
  else
    echo "Workflow is not a rerun from the beginning (tag: $WORKFLOW_TAG). Skipping env var operations."
    exit 0
  fi
else
  echo "Error: Invalid response from CircleCI API. Check your API token.Setting no tests to rerun"
  exit 0
fi

echo "Building env var"
# Build environment variable
ENV_KEY="BS_RERUN"
env_var=$(buildEnvironmentVariable "$ENV_KEY" "$CIRCLE_PIPELINE_ID" "$WORKFLOW_NAME" "$CIRCLE_USERNAME")

echo "Looking for environment variable: $env_var"
env_var_value=$(printenv "$env_var") || env_var_value=""

if [[ -n "$env_var_value" ]]; then
  set_env_var
  cleanup_env_var
else
  echo "No value found for environment variable: $env_var"
fi
