#!/usr/bin/env ruby
require 'rubygems'
require 'oauth2'
require 'cgi'

class CFClient

  @@domain_name = ENV["DOMAIN_NAME"]

  def initialize(client_id, client_secret, uaa_url)
    @client = OAuth2::Client.new(
      client_id,
      client_secret,
      :site => uaa_url)

    @token = @client.client_credentials.get_token;

  end

  def api_url

    return "https://api.#{@@domain_name}/v3"

  end

  def get_organization_by_name(org_name)

    org = nil

    response = @token.get("#{api_url}/organizations?names=#{org_name}")
    if response.parsed["pagination"]["total_pages"] == 1
      org = response.parsed['resources'][0]
    end

    return org

  end

  def get_organization_quota_by_name(org_name)

    quota = nil

    response = @token.get("#{api_url}/organization_quotas?names=#{org_name}")
    if response.parsed["pagination"]["total_pages"] == 1
      quota = response.parsed['resources'][0]
    end

    return quota

  end

  def get_organization_spaces(org_guid)

    response = @token.get("#{api_url}/spaces?organization_guids=#{(org_guid)}")
    spaces = response.parsed["resources"]

    return spaces
  end

  def get_users

    response = @token.get("#{api_url}/users?order_by=-created_at")
    users = response.parsed["resources"];

  end

  def add_user_to_org(user_guid, org_guid)

    role_type = "organization_user"

    # Add user to org
    req = {
      type: role_type,
      relationships: {
        user: {
          data: {
            guid: user_guid
          }
        },
        organization: {
          data: {
            guid: org_guid
          }
        }
      }
    }

    puts "Adding user_guid '#{user_guid}' to org_guid: #{org_guid}"

    response = @token.post(
      "#{api_url}/roles",
      headers: { 'Content-Type' => 'application/json' },
      body: req.to_json
    )
  
    puts "Added user_guid '#{user_guid}' to org_guid: #{org_guid}, response status: #{response.status}"

    return response
  end

  def create_organization(org_name, org_quota_definition_guid)
    # Step 1: Create the org
    create_req = {
      name: org_name
    }
  
    puts "Creating organization '#{org_name}' ..."
    response = @token.post(
      "#{api_url}/organizations",
      headers: { 'Content-Type' => 'application/json' },
      body: create_req.to_json
    )
  
    org = response.parsed
    org_guid = org["guid"]
  
    puts "Created organization '#{org_name}' with GUID: #{org_guid} response status: #{response.status} "
  
    # Step 2: Set quota
    self.set_org_quota(org_guid, org_quota_definition_guid)
    return org
  end

  def set_org_quota(org_guid, org_quota_definition_guid)

    quota_req = {
      data: [{ guid: org_guid }]
    }

    quota_url = "#{api_url}/organization_quotas/#{org_quota_definition_guid}/relationships/organizations"
   
    puts "Associating org_quota_definition_guid: #{org_quota_definition_guid} with org_guid: #{org_guid}..."
    response = @token.post(
      quota_url,
      headers: { 'Content-Type' => 'application/json' },
      body: quota_req.to_json
    )
  
    puts "Associated org_quota_definition_guid: #{org_quota_definition_guid} with org_guid: #{org_guid}, response status: #{response.status}"
  end

  def create_space(name, organization_guid, developer_guid, manager_guid, space_quota_guid)

    create_req = {
      name: name,
      relationships: {
        organization: {
          data: {
            guid: organization_guid
          }
        }
      }
    }

    puts "Creating space: #{name} in organization_guid: #{organization_guid}"
    response = @token.post(
      "#{api_url}/spaces",
      headers: { 'Content-Type' => 'application/json' },
      body: create_req.to_json
    )
    
    space = response.parsed
    space_guid = space["guid"]
    puts "Created space: #{name} in organization_guid: #{organization_guid} response status: #{response.status}"

    self.set_space_quota(space_guid, space_quota_guid)
    self.add_user_to_space_and_role(developer_guid, space_guid, "space_developer")
    self.add_user_to_space_and_role(manager_guid, space_guid, "space_manager")
    self.add_space_asg(space_guid, "public_networks_egress")
    self.add_space_asg(space_guid, "trusted_local_networks_egress")

  end

  def set_space_quota(space_guid, space_quota_guid)

    quota_req = {
      data: [{ guid: space_guid }]
    }

    puts "Associating space quota space_guid: #{space_guid}, space_quota_guid: #{space_quota_guid}..."

    response = @token.post(
      "#{api_url}/space_quotas/#{space_quota_guid}/relationships/spaces",
      headers: { 'Content-Type' => 'application/json' },
      body: quota_req.to_json
    )
    
    puts "Associated space quota space_guid: #{space_guid}, space_quota_guid: #{space_quota_guid} response status: #{response.status} "
  end

  def add_user_to_space_and_role(user_guid, space_guid, role_type)

    # Add user to role in space
    req = {
      type: role_type,
      relationships: {
        user: {
          data: {
            guid: user_guid
          }
        },
        space: {
          data: {
            guid: space_guid
          }
        }
      }
    }

    puts "Adding user_guid #{user_guid} to space #{space_guid} as role #{role_type}..."

    # Send request with explicit JSON headers
    response = @token.post(
      "#{api_url}/roles",
      headers: { 'Content-Type' => 'application/json' },
      body: req.to_json
    )
  
    puts "Added user_guid #{user_guid} to space #{space_guid} as role #{role_type} response status: #{response.status} "

  end

  def add_space_asg(space_guid, asg_name)

    puts "Finding guid for asg #{asg_name}..."
    asg_response = @token.get("#{api_url}/security_groups?names=#{CGI.escape asg_name}")
    asg = asg_response.parsed
    asg_guid = asg["resources"][0]["guid"]
    puts "Found guid for asg #{asg_name} as asg_guid #{asg_guid}"

    #Why only running_spaces?  Because globally_enabled.staging = true in stage/prod
    puts "Adding running_space guid: #{space_guid} to asg_guid #{asg_guid}..."

    create_req = {
      data: [{ guid: space_guid }]
    }

    url = "#{api_url}/security_groups/#{asg_guid}/relationships/running_spaces"

    response = @token.post(
      url,
      headers: { 'Content-Type' => 'application/json' },
      body: create_req.to_json
    )
    puts "Added running_space guid: #{space_guid} to asg_guid #{asg_guid} response status: #{response.status}"

    return response
  end

  def create_organization_space_quota_definition(org_guid, space_name)

    create_req = {
      name: space_name,
      relationships: {
        organization: {
          data: {
            guid: org_guid
          }
        }
      },
      apps: {
        total_memory_in_mb: 1024
      },
      services: {
        paid_services_allowed: false,
        total_service_instances: 10
      },
      routes: {
        total_routes: 10
      }
      
    }

    puts "Creating space quota #{space_name} for org_guid #{org_guid}..."
    response = @token.post(
      "#{api_url}/space_quotas",
      headers: { 'Content-Type' => 'application/json' },
      body: create_req.to_json
    )

    space_quota_definition = response.parsed
    space_quota_definition_guid = space_quota_definition["guid"]

    puts "Created space quota #{space_name} with GUID: #{space_quota_definition_guid}, response status: #{response.status} "

    return space_quota_definition
  
  end

  def get_organization_quota(org_guid)

    org_quota_definition_guid = get_org_quota_definition_guid(org_guid)

    puts "Finding organization quota #{org_quota_definition_guid}..."
    response = @token.get("#{api_url}/organization_quotas/#{org_quota_definition_guid}")
    quota = response.parsed
    puts "Found organization quota #{org_quota_definition_guid} " #with quota #{quota}"
    
    return quota
  end

  def get_org_quota_definition_guid(org_guid)

    puts "Finding organization quota guid for organization #{org_guid}..."
    response = @token.get("#{api_url}/organizations/#{org_guid}")
    organization_quota = response.parsed
    org_quota_definition_guid = organization_quota["relationships"]["quota"]["data"]["guid"]
    puts "Found organization quota guid for orginization #{org_guid} as #{org_quota_definition_guid}"
    
    return org_quota_definition_guid
  end

  def increase_org_quota(org)

    quota = get_organization_quota(org['guid'])
    quota_total_routes = quota["routes"]["total_routes"]
    quota_total_services = quota["services"]["total_service_instances"]
    quota_memory_limit = quota["apps"]["total_memory_in_mb"]
    org_spaces = get_organization_spaces(org['guid'])
    space_count = org_spaces.length
    computed_total_routes_services = 10 * space_count
    computed_memory_limit = 1024 * space_count

    create_req = {
      apps: {
        total_memory_in_mb: quota_memory_limit > computed_memory_limit ? quota_memory_limit : computed_memory_limit
      },
      services: {
        paid_services_allowed: true,
        total_service_instances: quota_total_services > computed_total_routes_services ? quota_total_services : computed_total_routes_services
      },
      routes: {
        total_routes: quota_total_routes > computed_total_routes_services ? quota_total_routes : computed_total_routes_services
      }
    }

    puts "Updating org quota definition #{org["name"]}..."
    response = @token.patch(
      "#{api_url}/organization_quotas/#{quota["guid"]}",
      headers: { 'Content-Type' => 'application/json' },
      body: create_req.to_json
    )

    org_quota_definition = response.parsed
    puts "Updated org quota #{org["name"]}, response status: #{response.status} "
     
  end

  def create_organization_quota(org_name)

    create_req = {
      name: org_name,
      apps: {
        total_memory_in_mb: 1024
      },
      services: {
        paid_services_allowed: false,
        total_service_instances: 10
      },
      routes: {
        total_routes: 10
      }
    }

    puts "Creating org quota #{org_name}..."
    response = @token.post(
      "#{api_url}/organization_quotas",
      headers: { 'Content-Type' => 'application/json' },
      body: create_req.to_json
    )

    org_quota_definition = response.parsed
    org_quota_definition_guid = org_quota_definition["guid"]

    puts "Created org quota #{org_name} with GUID: #{org_quota_definition_guid}, response status: #{response.status} "

    org_quota = response.parsed

  end

  def get_organization_space_quota_definitions(org_guid)

    space_quota_definitions = nil

    response = @token.get("#{api_url}/space_quotas?organization_guids=#{org_guid}")
    puts "Finding space quotas for org #{org_guid}..."
    if response.parsed["pagination"]["total_results"] != 0
      space_quota_definitions = response.parsed['resources']
      puts "Found #{response.parsed["pagination"]["total_results"]} space quotas for org #{org_guid}"
    end
    puts "Returning any found space quotas..."

    return space_quota_definitions

  end

  def get_organization_space_quota_definition_by_name(org_guid, name)

    space_quota_definition = nil

    space_quota_definitions = get_organization_space_quota_definitions(org_guid)

    puts "Finding quota definition named #{name}..."
    if space_quota_definitions
      space_quota_definitions.each do |quota_definition|
        if quota_definition['name'] == name
          space_quota_definition = quota_definition
          puts "Found quota definition named #{name}"
          break
        end
      end
    end

    return space_quota_definition

  end

  def organization_space_name_exists?(org_guid, space_name)

    response = @token.get("#{api_url}/spaces?organization_guids=#{org_guid}&names=#{CGI.escape space_name}")
    return response.parsed["pagination"]["total_results"] == 1

  end

end