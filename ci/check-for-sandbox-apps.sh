#!/bin/bash

set -uo pipefail

# Purpose
# Check for the presence of any applications currently deployed to a sandbox org in CF.  If an app is found, the org, space and app name are printed and exits non-zero.

# Log into CF as an admin
echo "Logging into ${CF_API} as user ${CF_ADMIN_USER}..."
cf login -a ${CF_API} -u ${CF_ADMIN_USER} -p "${CF_ADMIN_PASSWORD}" -o cloud-gov -s bots >/dev/null 2>&1

total_apps=0
output_lines=()

# Use the CF CLI since that has pagination built in, cf curl is a pain to loop in bash for pagination
org_names=$(cf orgs | tail -n +2)

while IFS= read -r org_name; do
  # Only process orgs starting with 'sandbox-'
  if [[ $org_name != sandbox-* ]]; then
    continue
  fi

  echo "Scanning sandbox ${org_name}..."
  org_guid=$(cf org "$org_name" --guid)

  # Get spaces in the org
  while IFS="|" read -r space_guid space_name; do
    # Get apps in the space
    apps=$(cf curl "/v3/apps?space_guids=$space_guid" | jq -r '.resources[].name')

    if [[ -n "$apps" ]]; then
      while IFS= read -r app_name; do
        echo "Application ${app_name} found in organization ${org_name} and space ${space_name}"
        output_lines+=("\"$org_name\",\"$space_name\",\"$app_name\"")
        ((total_apps++))
      done <<< "$apps"
    fi
  done < <(cf curl "/v3/spaces?organization_guids=$org_guid" | jq -r '.resources[] | "\(.guid)|\(.name)"')
done <<< "$org_names"

echo ""
echo "Results:"
# Print results
if (( total_apps > 0 )); then
  echo "Applications were found in:"
  printf "%s\n" "${output_lines[@]}"
  exit 1
else
  echo "No apps found in sandbox organizations. Carry on!"
  exit 0
fi
