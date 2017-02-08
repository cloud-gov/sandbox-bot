require_relative './cf_client'
require_relative './monitor_helper'
require 'slack-notifier'

include MonitorHelper

$stdout.sync = true

SANDBOX_ORG_NAME = 'sandbox'
SANDBOX_QUOTA_NAME = 'sandbox_quota'

@notifier = Slack::Notifier.new ENV["SLACK_HOOK"],
              channel: "#cloud-gov",
              username: "sandboxbot"

@cf_client = CFClient.new(ENV["CLIENT_ID"], ENV["CLIENT_SECRET"], ENV["UAA_URL"])
@environment = get_cloud_environment(ENV["UAA_URL"])

def process_new_users
  users = @cf_client.get_users

  users.each do |user|
    is_new_org = false

    email = user["entity"]["username"]
    next if !is_valid_email(email) || !is_whitelisted_email(email)

    sandbox_org = @cf_client.get_organization_by_name(SANDBOX_ORG_NAME)

    if !sandbox_org
      #check if org quota already exists - if not, create
      org_quota = @cf_client.get_organization_quota_by_name(SANDBOX_ORG_NAME)
      if !org_quota
        puts "Creating org quota for #{SANDBOX_ORG_NAME}"
        org_quota = @cf_client.create_organization_quota(SANDBOX_ORG_NAME)
      end
      sandbox_org = @cf_client.create_organization(SANDBOX_ORG_NAME, org_quota["metadata"]["guid"])

      msg = "Creating New Organization #{SANDBOX_ORG_NAME} on #{@environment}"
      puts msg
      if ENV["DO_SLACK"]
        begin
          @notifier.ping msg, icon_emoji: ":cloud:"
        rescue
          puts "Could not post #{msg} to slack"
        end
      end
      is_new_org = true
    end

    user_space_name = get_sandbox_space_name(email)
    # if this is a new org or the user space doesn't exist in the org - create one
    if is_new_org ||
      !@cf_client.organization_space_name_exists?(sandbox_org['metadata']['guid'], user_space_name)
      msg = "Setting up new sandbox user #{user["entity"]["username"]} in #{SANDBOX_ORG_NAME} on #{@environment}"
      puts msg

      # Send alert to slack
      if ENV["DO_SLACK"]
        begin
          @notifier.ping msg, icon_emoji: ":cloud:"
        rescue
          puts "Could not post #{msg} to slack"
        end
      end

      # add user to the parent org
      @cf_client.add_user_to_org(user["metadata"]["guid"], sandbox_org['metadata']["guid"])

      #get the sandbox space quoto definition for this org - if one doesn't exist, create it
      sandbox_org_space_quota_definition =
        @cf_client.get_organization_space_quota_definition_by_name(sandbox_org['metadata']['guid'], SANDBOX_QUOTA_NAME)

      if !sandbox_org_space_quota_definition
        sandbox_org_space_quota_definition =
        @cf_client.create_organization_space_quota_definition(sandbox_org['metadata']["guid"], SANDBOX_QUOTA_NAME)
      end

      # create user space using the first portion of the email address as the space name
      @cf_client.create_space(user_space_name, sandbox_org['metadata']["guid"],
          [user["metadata"]["guid"]], [user["metadata"]["guid"]],
          sandbox_org_space_quota_definition['metadata']['guid'])
      # increase the org quota
      if !is_new_org
        puts "Increasing org quota for #{SANDBOX_ORG_NAME} on #{@environment}"
        @cf_client.increase_org_quota(sandbox_org)
      end
    else
      puts "Space #{user_space_name} already exists on #{@environment} - skipping"
    end
  end
end

while true
  puts "Getting users on #{@environment}"
  process_new_users
  sleep(ENV["SLEEP_TIMEOUT"].to_i)
end
