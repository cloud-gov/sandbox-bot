#!/bin/bash

set -uo pipefail

# These are destructive acceptance tests which should only be run in STAGING, there are explicit checks for this, do not override them
# Requires a user with cloud_controller.admin access to run since it will be creating/deleting users, organizations and org quotas
# These are destructive to the `sandbox-fedramp`.  This org was chosen since it: wasn't in use, we have email access to the domain, should remain in the CSV file maintaining the list of verified gov agencies

# Log into CF as an admin
echo "Logging into ${CF_API} as user ${CF_ADMIN_USER}..."
cf login -a ${CF_API} -u ${CF_ADMIN_USER} -p "${CF_ADMIN_PASSWORD}" -o cloud-gov -s bots >/dev/null 2>&1

# Confirm that we're targeting the correct API
api_target=$(cf api | grep -i 'API endpoint' | awk '{print $3}')
if [[ "$api_target" != *"fr-stage"* ]]; then
  echo "### THIS IS A DESTRUCTIVE TEST to the sandbox-fedramp org, DO NOT RUN IN PRODUCTION ###"
  echo "Error: Not targeting staging. Current API endpoint: $api_target, exiting for your own safety."
  exit 1
fi

# Create a random 32-character password with hyphens
PASSWORD=$(cat /dev/urandom | base64 | tr -dc '0-9a-zA-Z' | head -c32)

# Create the user
echo "Creating CF user test.user@fedramp.gov with a random password..."
cf create-user "test.user@fedramp.gov" "$PASSWORD" >/dev/null 2>&1

# Sleep for 45 seconds, app runs every 30 seconds
echo "Sleeping test for 45 seconds to wait for sandbox-bot app to process the new user..."
sleep 45

# Observe the output from the app, it should create a new org, space and quotas within 30 seconds
ORG_NAME="sandbox-fedramp"
SPACE_NAME="test.user"
EXPECTED_ORG_QUOTA="sandbox-fedramp"
EXPECTED_SPACE_QUOTA="sandbox_quota"
REQUIRED_SECURITY_GROUPS=("public_networks_egress" "trusted_local_networks_egress")

echo "🔍 Checking for org '$ORG_NAME'..."
if cf orgs | grep -q "^$ORG_NAME$"; then
  echo "✅ Org '$ORG_NAME' found. Targeting..."
  cf target -o "$ORG_NAME" >/dev/null 2>&1
else
  echo "❌ Org '$ORG_NAME' not found."
fi

echo "🔍 Checking org quota for '$ORG_NAME'..."
org_quota=$(cf org "$ORG_NAME" | awk -F': ' '/quota:/ {print $2}' | xargs || echo "UNKNOWN")
if [[ "$org_quota" == "$EXPECTED_ORG_QUOTA" ]]; then
  echo "✅ Org quota is '$org_quota'"
else
  echo "❌ Org quota mismatch. Expected '$EXPECTED_ORG_QUOTA', got '$org_quota'"
fi

echo "🔍 Checking spaces for org '$ORG_NAME'..."
spaces_output=$(cf spaces)
space_count=$(echo "$spaces_output" | grep -c "^$SPACE_NAME$")
if [[ "$space_count" -eq 1 ]]; then
  echo "✅ Space '$SPACE_NAME' found."
  cf target -s "$SPACE_NAME" >/dev/null 2>&1
else
  echo "❌ Expected one space named '$SPACE_NAME', found $space_count"
fi

echo "🔍 Checking space quota for space '$SPACE_NAME'..."
space_quota=$(cf space "$SPACE_NAME" | awk -F': ' '/quota:/ {print $2}' | xargs || echo "UNKNOWN")
if [[ "$space_quota" == "$EXPECTED_SPACE_QUOTA" ]]; then
  echo "✅ Space quota is '$space_quota'"
else
  echo "❌ Space quota mismatch. Expected '$EXPECTED_SPACE_QUOTA', got '$space_quota'"
fi

echo "🔍 Verifying running security groups from 'cf space $SPACE_NAME' output..."
space_output=$(cf space "$SPACE_NAME")

for group in "${REQUIRED_SECURITY_GROUPS[@]}"; do
  if grep -A 10 "running security groups" <<< "$space_output" | grep -q "$group"; then
    echo "✅ Running security group '$group' is listed in space config"
  else
    echo "❌ Missing required running security group '$group' in space config"
  fi
done

echo "🔍 Checking org quota resource limits from 'cf org-quota $ORG_NAME'..."
org_quota_output=$(cf org-quota "$ORG_NAME")

# Total memory
total_memory=$(awk -F': ' '/total memory:/ {print $2}' <<< "$org_quota_output" | xargs)
if [[ "$total_memory" == "1G" ]]; then
  echo "✅ Total memory is 1G"
else
  echo "❌ Total memory mismatch: Expected '1G', got '$total_memory'"
fi

# Routes
routes=$(awk -F': ' '/routes:/ {print $2}' <<< "$org_quota_output" | xargs)
if [[ "$routes" == "10" ]]; then
  echo "✅ Routes is 10"
else
  echo "❌ Routes mismatch: Expected '10', got '$routes'"
fi

# Service instances
services=$(awk -F': ' '/service instances:/ {print $2}' <<< "$org_quota_output" | xargs)
if [[ "$services" == "10" ]]; then
  echo "✅ Service instances is 10"
else
  echo "❌ Service instances mismatch: Expected '10', got '$services'"
fi

PASSWORD=$(cat /dev/urandom | base64 | tr -dc '0-9a-zA-Z' | head -c32)
echo "Creating a second CF user test.user2@fedramp.gov with a random password..."
cf create-user "test.user2@fedramp.gov" "$PASSWORD" >/dev/null 2>&1

# Sleep for 45 seconds, app runs every 30 seconds
echo "Sleeping test for 45 seconds to wait for sandbox-bot app to process the new user..."
sleep 45

# Verify the second space was created

SPACE_NAMES=("test.user" "test.user2")

echo "🔍 Verifying exactly two spaces named 'test.user' and 'test.user2'..."
spaces_output=$(cf spaces | awk 'NR>3' | xargs -n1)
actual_spaces=($(echo "$spaces_output"))
expected_spaces_sorted=($(printf "%s\n" "${SPACE_NAMES[@]}" | sort))
actual_spaces_sorted=($(printf "%s\n" "${actual_spaces[@]}" | sort))

if [[ "${#actual_spaces_sorted[@]}" -eq 2 && "${actual_spaces_sorted[*]}" == "${expected_spaces_sorted[*]}" ]]; then
  echo "✅ Found exactly the expected spaces: ${SPACE_NAMES[*]}"
else
  echo "❌ Space mismatch."
  echo "   Expected: ${SPACE_NAMES[*]}"
  echo "   Found: ${actual_spaces[*]}"
fi

for space in "${SPACE_NAMES[@]}"; do
  echo "🔍 Targeting space '$space'..."
  cf target -s "$space" >/dev/null 2>&1

  echo "🔍 Checking space quota for space '$space'..."
  space_quota=$(cf space "$space" | awk -F': ' '/quota:/ {print $2}' | xargs || echo "UNKNOWN")
  if [[ "$space_quota" == "$EXPECTED_SPACE_QUOTA" ]]; then
    echo "✅ Space quota is '$space_quota'"
  else
    echo "❌ Space quota mismatch. Expected '$EXPECTED_SPACE_QUOTA', got '$space_quota'"
  fi

  echo "🔍 Verifying running security groups from 'cf space $space' output..."
  space_output=$(cf space "$space")

  for group in "${REQUIRED_SECURITY_GROUPS[@]}"; do
    if grep -A 10 "running security groups" <<< "$space_output" | grep -q "$group"; then
      echo "✅ Running security group '$group' is listed in space config"
    else
      echo "❌ Missing required running security group '$group' in space config"
    fi
  done
done

echo "🔍 Checking org quota resource limits from 'cf org-quota $ORG_NAME'..."
org_quota_output=$(cf org-quota "$ORG_NAME")

# Total memory
total_memory=$(awk -F': ' '/total memory:/ {print $2}' <<< "$org_quota_output" | xargs)
if [[ "$total_memory" == "2G" ]]; then
  echo "✅ Total memory is 2G"
else
  echo "❌ Total memory mismatch: Expected '2G', got '$total_memory'"
fi

# Routes
routes=$(awk -F': ' '/routes:/ {print $2}' <<< "$org_quota_output" | xargs)
if [[ "$routes" == "20" ]]; then
  echo "✅ Routes is 20"
else
  echo "❌ Routes mismatch: Expected '20', got '$routes'"
fi

# Service instances
services=$(awk -F': ' '/service instances:/ {print $2}' <<< "$org_quota_output" | xargs)
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
  echo "### THIS IS A DESTRUCTIVE TEST to the sandbox-fedramp org, DO NOT RUN IN PRODUCTION ###"
  echo "Error: Not targeting staging. Current API endpoint: $api_target, exiting for your own safety."
  exit 1
fi

cf delete-user "test.user@fedramp.gov" -f
cf delete-user "test.user2@fedramp.gov" -f

## Remove org
ORG_NAME="sandbox-fedramp"
cf delete-org "$ORG_NAME" -f 

## Clean up org quota
EXPECTED_ORG_QUOTA="sandbox-fedramp"
cf delete-org-quota "$EXPECTED_ORG_QUOTA" -f

echo "~fin~"