#!/usr/bin/env ruby
require 'rubygems'
require 'oauth2'
require 'json'
require 'slack-notifier'

$stdout.sync = true


client = OAuth2::Client.new(
  ENV["CLIENT_ID"],
  ENV["CLIENT_SECRET"],
  :site => ENV["UAA_URL"])

@notifier = Slack::Notifier.new ENV["SLACK_HOOK"],
              channel: "#cloud-gov",
              username: "sandboxbot"
@token = client.client_credentials.get_token
@domains = JSON.parse(ENV["DOMAINS"])
@last_user_date = nil

def load_spaces
  @domains.each do |d|
    response = @token.get(
      "https://api.cloud.gov/v2/organizations/" + d["guid"] + "/spaces",
      :params => { 'results-per-page' => '100' })
    d["spaces"] = response.parsed["resources"]
  end
end

def get_users
  response = @token.get(
    "https://api.cloud.gov/v2/users?order-direction=desc"
  )
  last_user_date = nil
  users = response.parsed["resources"]
  users.each do |u|
    # Break if the user is older than what we saw already
    break if @last_user_date && @last_user_date > u["metadata"]["created_at"]
    # Lets capture last time stamp to only query after that
    if last_user_date.nil? || last_user_date < u["metadata"]["created_at"]
      last_user_date = u["metadata"]["created_at"]
    end

    next if u["entity"]["username"].nil? || u["entity"]["username"].index("@").nil?
    email = u["entity"]["username"].split("@")
    domain = @domains.detect { |d| d["domain"] == email[1].downcase}
    if domain
      unless domain["spaces"].map { |s| s["entity"]["name"] }.include?(email[0].downcase)
        # Print status
        msg = "Setting up new sandbox user #{u["entity"]["username"]} in #{domain["space"]}"
        puts msg
        # Send alert to slack
        if ENV["DO_SLACK"]
          @notifier.ping msg, icon_emoji: ":cloud:"
        end

        # Add user to org
        @token.put(
          "https://api.cloud.gov/v2/organizations/" +
          domain["guid"] +
          "/users/" +
          u["metadata"]["guid"])

        # Create space
        req = {
          name: email[0].downcase,
          organization_guid: domain["guid"],
          developer_guids: [u["metadata"]["guid"]],
          manager_guids: [u["metadata"]["guid"]]
        }

        sr = @token.post("https://api.cloud.gov/v2/spaces",
          body: req.to_json)

        # Reload the spaces
        load_spaces
      end
    end
  end

  # bubble up last_user_date
  @last_user_date = last_user_date
end

load_spaces
while true
  puts "Getting users"
  get_users
  puts @last_user_date
  sleep(ENV["SLEEP_TIMEOUT"].to_i)
end
