require_relative './cf_client'
require_relative './monitor_helper'
require 'slack-notifier'

include MonitorHelper

$stdout.sync = true

SANDBOX_QUOTA_NAME = 'sandbox_quota'

@notifier = Slack::Notifier.new ENV["SLACK_HOOK"],
              channel: "#cloud-gov",
              username: "sandboxbot"

@cf_client = CFClient.new(ENV["CLIENT_ID"], ENV["CLIENT_SECRET"], ENV["UAA_URL"])
@last_user_date = nil
@environment = get_cloud_environment(ENV["UAA_URL"])

def send_slack_notification(msg, sandbox_org_name)
  puts msg
  if (ENV["DO_SLACK"] === true || ENV["DO_SLACK"].downcase == "true")
    begin
      @notifier.ping msg, icon_emoji: ":cloud:"
    rescue
      puts "Could not post #{msg} to slack"
    end
  end
end

def process_new_users

  last_user_date = nil
	users = @cf_client.get_users

  users.each do |user|

    is_new_org = false

    # save the date of the most recent user added
    if last_user_date.nil? || last_user_date < user["created_at"]
      last_user_date = user["created_at"]
    end

    #break out of processing if we already processed this user in previous run
    break if @last_user_date && @last_user_date >= user["created_at"]

  	email = user["username"]
    next if !is_valid_email(email) || !is_allowlisted_email(email)

    # extract the domain name from the email address
    sandbox_org_name = get_sandbox_org_name(email)

    sandbox_org = @cf_client.get_organization_by_name(sandbox_org_name)

    if !sandbox_org
      #check if org quota already exists - if not, create
      org_quota = @cf_client.get_organization_quota_by_name(sandbox_org_name)
      if !org_quota
        puts "Creating org quota for #{sandbox_org_name}"
        org_quota = @cf_client.create_organization_quota(sandbox_org_name)
      end
    	sandbox_org = @cf_client.create_organization(sandbox_org_name, org_quota["guid"])

      send_slack_notification(msg, sandbox_org_name)

      is_new_org = true
    end

    user_space_name = get_sandbox_space_name(email)
    # if this is a new org or the user space doesn't exist in the org - create one
    if is_new_org ||
      !@cf_client.organization_space_name_exists?(sandbox_org['guid'], user_space_name)

      msg = "Setting up new sandbox user #{user["username"]} in #{sandbox_org_name} on #{@environment}"
      send_slack_notification(msg, sandbox_org_name)

      # add user to the parent org
      @cf_client.add_user_to_org(user["guid"], sandbox_org["guid"])

      # get the sandbox space quota definition for this org - if one doesn't exist, create it
      sandbox_org_space_quota_definition =
        @cf_client.get_organization_space_quota_definition_by_name(sandbox_org['guid'], SANDBOX_QUOTA_NAME)

      if !sandbox_org_space_quota_definition
        sandbox_org_space_quota_definition =
        @cf_client.create_organization_space_quota_definition(sandbox_org["guid"], SANDBOX_QUOTA_NAME)
      end

      # create user space using the first portion of the email address as the space name
      @cf_client.create_space(user_space_name, sandbox_org["guid"],
          user["guid"], user["guid"],
          sandbox_org_space_quota_definition['guid'])
      # increase the org quota
      if !is_new_org
        puts "Increasing org quota for #{sandbox_org_name} on #{@environment}"
        @cf_client.increase_org_quota(sandbox_org)
      end
    else
      puts "Space #{user_space_name} already exists on #{@environment} - skipping"
    end
  end

  # save the date of the most recent user processed so that we can
  # ignore users added before that date on the next iteration

  @last_user_date = last_user_date

end

while true
  puts "Getting users on #{@environment}"
  process_new_users
  puts @last_user_date
  sleep(ENV["SLEEP_TIMEOUT"].to_i)
end
