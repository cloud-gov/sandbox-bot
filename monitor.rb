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
@org_quotas = []

def load_org_quotas
  current_page = 1
  total_pages = 1
  while total_pages >= current_page
    response = @token.get(
      "https://api.cloud.gov/v2/quota_definitions",
      :params => { 'results-per-page' => '100', 'page' => current_page })

    total_pages = response.parsed["total_pages"].to_i
    current_page += 1
    @org_quotas << response.parsed["resources"]
  end
  @org_quotas.flatten!(1)
end

def get_org_quota(org_name)
  quota = @org_quotas.detect { |q| q["entity"]["name"] == org_name }
end

def create_org_quota(domain)
  puts "Creating org quota for #{domain["space"]}"
  space_count = domain["spaces_count"]
  total_routes_services = 10 * space_count
  memory_limit = 1024 * space_count
  req = {
    name: domain["space"],
    non_basic_services_allowed: true,
    total_services: total_routes_services,
    total_routes: total_routes_services,
    memory_limit: memory_limit,
    instance_memory_limit: -1
  }

  # do create
  create_response = @token.post("https://api.cloud.gov/v2/quota_definitions",
    body: req.to_json)

  # assign quota to org
  req = {
    name: domain["space"],
    quota_definition_guid: create_response.parsed["metadata"]["guid"]
  }
  assign_response = @token.put("https://api.cloud.gov/v2/organizations/" + domain["guid"],
    body: req.to_json)
end

def increase_org_quota(domain)
  puts "Setting new org quota limits for #{domain["space"]}"
  quota = get_org_quota(domain["space"])
  update_url = quota["metadata"]["url"]
  quota_total_routes = quota["entity"]["total_routes"]
  quota_total_services = quota["entity"]["total_services"]
  quota_memory_limit = quota["entity"]["memory_limit"]
  space_count = domain["spaces_count"]
  computed_total_routes_services = 10 * space_count
  computed_memory_limit = 1024 * space_count
  req = {
    name: domain["space"],
    non_basic_services_allowed: true,
    total_services: quota_total_services > computed_total_routes_services ? quota_total_services : computed_total_routes_services,
    total_routes: quota_total_routes > computed_total_routes_services ? quota_total_routes : computed_total_routes_services,
    memory_limit: quota_memory_limit > computed_memory_limit ? quota_memory_limit : computed_memory_limit,
    instance_memory_limit: -1
  }
  # Update quota definition
  response = @token.put("https://api.cloud.gov/v2/quota_definitions/" + quota["metadata"]["guid"],
    body: req.to_json)

end

def create_space_quota(domain)
  req = {
    name: "sandbox_quota",
    non_basic_services_allowed: false,
    total_services: 10,
    total_routes: 10,
    memory_limit: 1024,
    organization_guid: domain["guid"]
  }
  # Create sandbox_quota for a particular org
  response = @token.post("https://api.cloud.gov/v2/space_quota_definitions",
    body: req.to_json)

  return response.parsed["metadata"]["guid"]

end

def set_space_quotas(domain, space_quota_guid)
  domain["spaces"].each do |space|
    # Assign space to space quota
    response = @token.put("https://api.cloud.gov/v2/space_quota_definitions/" +
      space_quota_guid + "/spaces/" +
      space["metadata"]["guid"])
  end
end

def load_spaces
  @domains.each do |d|
    current_page = 1
    total_pages = 1
    d["spaces"] = []
    while total_pages >= current_page
      response = @token.get(
        "https://api.cloud.gov/v2/organizations/" + d["guid"] + "/spaces",
        :params => { 'results-per-page' => '100', 'page' => current_page })

      total_pages = response.parsed["total_pages"].to_i
      current_page += 1
      d["spaces"] << response.parsed["resources"]
    end
    d["spaces"].flatten!(1)
    d["spaces_count"] = d["spaces"].count
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
    domain = @domains.detect { |d| email[1].downcase.include? d["domain"] }
    if domain
      unless domain["spaces"].map { |s| s["entity"]["name"].downcase }.include?(email[0].downcase)
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

        # Create space with space quota
        req = {
          name: email[0].downcase,
          organization_guid: domain["guid"],
          developer_guids: [u["metadata"]["guid"]],
          manager_guids: [u["metadata"]["guid"]],
          space_quota_definition_guid: domain["space_quota_guid"]
        }

        sr = @token.post("https://api.cloud.gov/v2/spaces",
          body: req.to_json)

        # Reload the spaces
        load_spaces
        # Increase org quota
        increase_org_quota(domain)
        # Reload org quotas
        load_org_quotas
      end
    end
  end

  # bubble up last_user_date
  @last_user_date = last_user_date
end

load_spaces
load_org_quotas
# If we get init command, set proper org and space quotas
# for existing org/spaces for each domain
if ARGV.count && ARGV[0] == "init"
  touched_orgs = []
  @domains.each do |domain|
    # skip if we already setup space quota
    if !domain["space_quota_guid"]
      org_name = domain["space"]
      quota_url = nil
      # Only process sandbox orgs, and only if we haven't done it already
      if /^sandbox/ =~ org_name && ! touched_orgs.include?(org_name)
        quota = get_org_quota(org_name)
        if quota
          increase_org_quota(domain)
        else
          create_org_quota(domain)
        end
        touched_orgs << org_name
        if ! domain["space_quota_guid"]
          # create a space quota
          space_quota_guid = create_space_quota(domain)
          # output space quota guid so we can update the DOMAINS env in app
          puts "Update DOMAINS env: \"domain\":\"#{domain["domain"]}\" with \"space_quota_guid\":\"#{space_quota_guid}\""
          # assign quota to existing spaces
          set_space_quotas(domain, space_quota_guid)
        end
      end
    end
  end
else
  while true
    puts "Getting users"
    get_users
    puts @last_user_date
    sleep(ENV["SLEEP_TIMEOUT"].to_i)
  end
end