#!/bin/bash

set -uo pipefail

# Requires a user with cloud_controller.admin access to run since it will be creating/deleting users, organizations and org quotas
# These are destructive to the `sandbox-test`, this agency (test.gov) does not exist and is added manually to the CSV results specifically for testing.  

cleanup_sandbox_resources() {
  local user1="test.user@test.gov"
  local user2="test.user2@test.gov"
  local org_name="sandbox-test"
  local org_quota="sandbox-test"

  echo "🔧 Deleting users..."
  cf delete-user "$user1" -f
  cf delete-user "$user2" -f

  #Check that org and org quota are safe to delete
  check_org_is_safe_to_remove

  echo "🏢 Deleting organization '$org_name'..."
  cf delete-org "$org_name" -f

  echo "📉 Deleting org quota '$org_quota'..."
  cf delete-org-quota "$org_quota" -f
}

check_org_is_safe_to_remove() {

  # Check if the org exists
  if ! cf org "$ORG_NAME" >/dev/null 2>&1; then
    echo "🔍 Org '${ORG_NAME}' not found, safe to run cleanup."
    return
  fi

  # Verifying exactly 0 or two spaces named 'test.user' and 'test.user2'..."
  cf target -o "$ORG_NAME" >/dev/null 2>&1
  spaces_output=$(cf spaces | awk 'NR>3' | xargs -n1)
  actual_spaces=($(echo "$spaces_output"))
  expected_spaces_sorted=($(printf "%s\n" "${SPACE_NAMES[@]}" | sort))
  actual_spaces_sorted=($(printf "%s\n" "${actual_spaces[@]}" | sort))

  if [[ "${#actual_spaces_sorted[@]}" -eq 0 || ("${#actual_spaces_sorted[@]}" -eq 2 && "${actual_spaces_sorted[*]}" == "${expected_spaces_sorted[*]}" ) ]]; then
    echo "🔍 Spaces found '${actual_spaces_sorted[*]}', safe to run cleanup."
    return
  fi

  # If you get to this point, the org exists but there are other spaces
  echo "❌ Cancelling clean up: expected spaces: '${expected_spaces_sorted[*]}', got '${actual_spaces_sorted[*]}'"
  exit 1
}

# Set variables
ORG_NAME="sandbox-test"
SPACE_NAME="test.user"
EXPECTED_ORG_QUOTA="sandbox-test"
EXPECTED_SPACE_QUOTA="sandbox_quota"
REQUIRED_SECURITY_GROUPS=("public_networks_egress" "trusted_local_networks_egress")
SPACE_NAMES=("test.user" "test.user2")


# Log into CF as an admin
echo "Logging into ${CF_API} as user ${CF_ADMIN_USER}..."
cf login -a ${CF_API} -u ${CF_ADMIN_USER} -p "${CF_ADMIN_PASSWORD}" -o cloud-gov -s bots >/dev/null 2>&1

# Confirm that we're targeting the correct API
api_target=$(cf api | grep -i 'API endpoint' | awk '{print $3}')
if [[ "$api_target" != *"fr-stage"* ]]; then
  echo "Error: Not targeting staging. Current API endpoint: $api_target, exiting for your own safety."
  exit 1
fi

# Cleanup from a previous run in case it errored out
cleanup_sandbox_resources

# Create a random 32-character password with hyphens
PASSWORD=$(cat /dev/urandom | base64 | tr -dc '0-9a-zA-Z' | head -c32)

# Create the user
echo "Creating CF user test.user@test.gov with a random password..."
cf create-user "test.user@test.gov" "$PASSWORD" >/dev/null 2>&1

# Observe the output from the app, it should create a new org, space and quotas within 30 seconds
MAX_ATTEMPTS=20
SLEEP_SECONDS=5

attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  echo "Attempt $attempt: 🔍 Checking for org '$ORG_NAME'..."

  if cf org "$ORG_NAME" &>/dev/null; then
    echo "✅ Organization '$ORG_NAME' found."
    cf target -o "$ORG_NAME" >/dev/null 2>&1
    break
  fi

  echo "⏳ Org '$ORG_NAME' not found. Retrying in $SLEEP_SECONDS seconds..."
  sleep "$SLEEP_SECONDS"
  ((attempt++))
done

if (( attempt > MAX_ATTEMPTS )); then
  echo "❗️Failed to find org '$ORG_NAME' after $MAX_ATTEMPTS attempts."
  exit 1
fi

echo "🔍 Checking org quota for '$ORG_NAME'..."
org_quota=$(cf org "$ORG_NAME" | awk -F': ' '/quota:/ {print $2}' | tr -d '[:space:]' || echo "UNKNOWN")
if [[ "$org_quota" == "$EXPECTED_ORG_QUOTA" ]]; then
  echo "✅ Org quota is '$org_quota'"
else
  echo "❌ Org quota mismatch. Expected '$EXPECTED_ORG_QUOTA', got '$org_quota'"
fi


echo "🔍 Checking org quota resource limits from 'cf org-quota $ORG_NAME'..."
org_quota_output=$(cf org-quota "$ORG_NAME")

# Total memory
total_memory=$(awk -F': ' '/total memory:/ {print $2}' <<< "$org_quota_output" | tr -d '[:space:]')
if [[ "$total_memory" == "1G" ]]; then
  echo "✅ Total memory is 1G"
else
  echo "❌ Total memory mismatch: Expected '1G', got '$total_memory'"
fi

# Routes
routes=$(awk -F': ' '/routes:/ {print $2}' <<< "$org_quota_output" | tr -d '[:space:]')
if [[ "$routes" == "10" ]]; then
  echo "✅ Routes is 10"
else
  echo "❌ Routes mismatch: Expected '10', got '$routes'"
fi

# Service instances
services=$(awk -F': ' '/service instances:/ {print $2}' <<< "$org_quota_output" | tr -d '[:space:]')
if [[ "$services" == "10" ]]; then
  echo "✅ Service instances is 10"
else
  echo "❌ Service instances mismatch: Expected '10', got '$services'"
fi

PASSWORD=$(cat /dev/urandom | base64 | tr -dc '0-9a-zA-Z' | head -c32)
echo "Creating a second CF user test.user2@test.gov with a random password..."
cf create-user "test.user2@test.gov" "$PASSWORD" >/dev/null 2>&1


MAX_ATTEMPTS=20
SLEEP_SECONDS=5

attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  echo "Attempt $attempt: 🔍 Verifying exactly two spaces named 'test.user' and 'test.user2'..."

  spaces_output=$(cf spaces | awk 'NR>3' | xargs -n1)
  actual_spaces=($(echo "$spaces_output"))
  expected_spaces_sorted=($(printf "%s\n" "${SPACE_NAMES[@]}" | sort))
  actual_spaces_sorted=($(printf "%s\n" "${actual_spaces[@]}" | sort))

  if [[ "${#actual_spaces_sorted[@]}" -eq 2 && "${actual_spaces_sorted[*]}" == "${expected_spaces_sorted[*]}" ]]; then
    echo "✅ Found exactly the expected spaces: ${SPACE_NAMES[*]}"
    break
  fi

  echo "⏳ Spaces '${SPACE_NAMES[*]}' not found. Retrying in $SLEEP_SECONDS seconds..."
  sleep "$SLEEP_SECONDS"
  ((attempt++))
done

if (( attempt > MAX_ATTEMPTS )); then
  echo "❗️Failed to find spaces '${SPACE_NAMES[*]}' after $MAX_ATTEMPTS attempts."
  exit 1
fi

for space in "${SPACE_NAMES[@]}"; do
  echo "🔍 Targeting space '$space'..."
  cf target -s "$space" >/dev/null 2>&1

  echo "🔍 Checking space quota for space '$space'..."
  space_quota=$(cf space "$space" | awk -F': ' '/quota:/ {print $2}' | tr -d '[:space:]' || echo "UNKNOWN")
  if [[ "$space_quota" == "$EXPECTED_SPACE_QUOTA" ]]; then
    echo "✅ Space quota is '$space_quota'"
  else
    echo "❌ Space quota mismatch. Expected '$EXPECTED_SPACE_QUOTA', got '$space_quota'"
  fi

  echo "🔍 Verifying running security groups from 'cf space $space' output..."
  space_output=$(cf space "$space")
  running_groups=$(awk -F': ' '/running security groups:/ {print $2}' <<< "$space_output" | tr -d '[:space:]')

  for group in "${REQUIRED_SECURITY_GROUPS[@]}"; do
    if grep -q "$group" <<< "$running_groups"; then
      echo "✅ Running security group '$group' is listed in space config"
    else
      echo "❌ Missing required running security group '$group' in space config"
    fi
  done
done

echo "🔍 Checking org quota resource limits from 'cf org-quota $ORG_NAME'..."
org_quota_output=$(cf org-quota "$ORG_NAME")

# Total memory
total_memory=$(awk -F': ' '/total memory:/ {print $2}' <<< "$org_quota_output" | tr -d '[:space:]')
if [[ "$total_memory" == "2G" ]]; then
  echo "✅ Total memory is 2G"
else
  echo "❌ Total memory mismatch: Expected '2G', got '$total_memory'"
fi

# Routes
routes=$(awk -F': ' '/routes:/ {print $2}' <<< "$org_quota_output" | tr -d '[:space:]')
if [[ "$routes" == "20" ]]; then
  echo "✅ Routes is 20"
else
  echo "❌ Routes mismatch: Expected '20', got '$routes'"
fi

# Service instances
services=$(awk -F': ' '/service instances:/ {print $2}' <<< "$org_quota_output" | tr -d '[:space:]')
if [[ "$services" == "20" ]]; then
  echo "✅ Service instances is 20"
else
  echo "❌ Service instances mismatch: Expected '20', got '$services'"
fi

echo "🎯 Finished all checks."


## Clean up users
echo "Cleaning up resources from the test..."

# Confirm that we're targeting the correct API
api_target=$(cf api | grep -i 'API endpoint' | awk '{print $3}')
if [[ "$api_target" != *"fr-stage"* ]]; then
  echo "Error: Not targeting staging. Current API endpoint: $api_target, exiting for your own safety."
  exit 1
fi

cleanup_sandbox_resources

echo "~fin~"