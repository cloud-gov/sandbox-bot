#!/usr/bin/env ruby
require 'rubygems'
require 'oauth2'

class CFClient

  @@domain_name = 'cloud.gov'

	def initialize(client_id, client_secret, uaa_url)
    @client = OAuth2::Client.new(
      client_id,
      client_secret,
      :site => uaa_url)

		@token = @client.client_credentials.get_token;

	end

  def api_url

    return "https://api.#{@@domain_name}/v2"

  end

  def get_organizations

    response = @token.get("#{api_url}/organizations")
    orgs = response.parsed

  end

  def get_organization_by_name(org_name)

    org = nil

    response = @token.get("#{api_url}/organizations?q=name:#{org_name}")
    if response.parsed["total_results"] == 1
      org = response.parsed['resources'][0]
    end

    return org

  end

  def get_organization_spaces(org_guid)

    response = @token.get("#{api_url}/organizations/#{(org_guid)}/spaces")
    spaces = response.parsed["resources"]

  end

  def get_users

    response = @token.get("#{api_url}/users?order-direction=desc")
    users = response.parsed["resources"];

  end

  def add_user_to_org(org_guid, user_guid)

    # Add user to org
    @token.put("#{api_url}/organizations/#{org_guid}/users/#{user_guid}")

  end


  def create_organization(org_name, quota_definition_guid)

    req = {
      name: org_name,
      quota_definition_guid: quota_definition_guid
    }

    response = @token.post("#{api_url}/organizations", body: req.to_json)
    org = response.parsed

  end

  def create_space(name, organization_guid, developer_guids, manager_guids, space_quota_guid)

    req = {
      name: name,
      organization_guid: organization_guid,
      developer_guids: developer_guids,
      manager_guids: manager_guids,
      space_quota_definition_guid: space_quota_guid
    }
    sr = @token.post("#{api_url}/spaces",
        body: req.to_json)

  end


  def get_organization_quota(org_guid)

    response = @token.get("#{api_url}/quota_definitions/#{org_guid}")
    quota = response.parsed

  end

  def increase_org_quota(org)

    puts "Setting new org quota limits for #{org['entity']['name']}"

    quota = get_organization_quota(org['metadata']['guid'])
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
    response = @token.put("#{api_url}/quota_definitions/" + quota["metadata"]["guid"],
      body: req.to_json)

  end

  def create_organization_quota(org_name)

    puts "Creating org quota for #{org_name}"

    req = {
      name: org_name,
      non_basic_services_allowed: false,
      total_services: 10,
      total_routes: 10,
      memory_limit: 1024,
      instance_memory_limit: -1
    }

    response = @token.post("#{api_url}/quota_definitions", body: req.to_json)
    org_quota = response.parsed

  end

end
