require 'webmock/rspec'
require 'spec_helper'
require_relative '../cf_client'

RSpec.describe CFClient do
  let(:client_id)     { "fake-client-id" }
  let(:client_secret) { "fake-client-secret" }
  let(:uaa_url)       { "https://fake-uaa.example.com" }
  let(:domain_name)   { "example.com" }
  let(:cf_client)     { described_class.new(client_id, client_secret, uaa_url) }

  let(:token_double) do
    instance_double(OAuth2::AccessToken)
  end

  let(:org_response) do
    {
      "pagination" => { "total_pages" => 1 },
      "resources" => [{ "guid" => "org-guid", "name" => "test-org" }]
    }
  end

  let(:quota_response) do
    {
      "pagination" => { "total_pages" => 1 },
      "resources" => [{ "guid" => "quota-guid", "name" => "test-quota" }]
    }
  end

  before do
    ENV["DOMAIN_NAME"] = domain_name

    # Stub token retrieval
    allow_any_instance_of(OAuth2::Client)
      .to receive_message_chain(:client_credentials, :get_token)
      .and_return(token_double)
  end

  describe "#api_url" do
    it "returns the correct API URL from ENV" do
      expect(cf_client.api_url).to eq("https://api.example.com/v3")
    end
  end

  describe "#get_organization_by_name" do
    it "returns the organization if it exists" do
      allow(token_double).to receive(:get)
        .with("https://api.example.com/v3/organizations?names=test-org")
        .and_return(instance_double("OAuth2::Response", parsed: org_response))

      org = cf_client.get_organization_by_name("test-org")
      expect(org["guid"]).to eq("org-guid")
      expect(org["name"]).to eq("test-org")
    end
  end

  describe "#get_organization_quota_by_name" do
    it "returns the organization quota if it exists" do
      allow(token_double).to receive(:get)
        .with("https://api.example.com/v3/organization_quotas?names=test-quota")
        .and_return(instance_double("OAuth2::Response", parsed: quota_response))

      quota = cf_client.get_organization_quota_by_name("test-quota")
      expect(quota["guid"]).to eq("quota-guid")
      expect(quota["name"]).to eq("test-quota")
    end
  end

  describe "#get_organization_spaces" do
    it "returns the list of spaces for the given org GUID" do
      space_response = {
        "resources" => [
          { "guid" => "space-1", "name" => "dev-space" },
          { "guid" => "space-2", "name" => "prod-space" }
        ]
      }

      allow(token_double).to receive(:get)
        .with("https://api.example.com/v3/spaces?organization_guids=org-guid")
        .and_return(instance_double("OAuth2::Response", parsed: space_response))

      spaces = cf_client.get_organization_spaces("org-guid")
      expect(spaces.size).to eq(2)
      expect(spaces.map { |s| s["guid"] }).to include("space-1", "space-2")
    end
  end

  describe "#get_users" do
    it "returns a list of users ordered by creation date" do
      users_response = {
        "resources" => [
          { "guid" => "user-1", "username" => "alice" },
          { "guid" => "user-2", "username" => "bob" }
        ]
      }

      allow(token_double).to receive(:get)
        .with("https://api.example.com/v3/users?order_by=-created_at")
        .and_return(instance_double("OAuth2::Response", parsed: users_response))

      users = cf_client.get_users
      expect(users.size).to eq(2)
      expect(users.map { |u| u["username"] }).to contain_exactly("alice", "bob")
    end
  end

  describe "#add_user_to_org" do
    it "sends a POST request to add a user to an organization and returns the response" do
      user_guid = "user-123"
      org_guid = "org-456"
      role_type = "organization_user"

      expected_body = {
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
      }.to_json

      mock_response = instance_double("OAuth2::Response", status: 201, parsed: { "role" => "created" })

      expect(token_double).to receive(:post)
        .with(
          "https://api.example.com/v3/roles",
          headers: { "Content-Type" => "application/json" },
          body: expected_body
        )
        .and_return(mock_response)

      response = cf_client.add_user_to_org(user_guid, org_guid)
      expect(response).to eq(mock_response)
    end
  end

  describe "#set_org_quota" do
    it "sends a POST request to associate a quota with an organization" do
      org_guid = "org-789"
      quota_guid = "quota-123"
      expected_body = {
        data: [{ guid: org_guid }]
      }.to_json

      mock_response = instance_double("OAuth2::Response", status: 200)

      expect(token_double).to receive(:post)
        .with(
          "https://api.example.com/v3/organization_quotas/#{quota_guid}/relationships/organizations",
          headers: { "Content-Type" => "application/json" },
          body: expected_body
        ).and_return(mock_response)

      cf_client.set_org_quota(org_guid, quota_guid)
    end
  end

  describe "#create_organization" do
    it "creates an organization and sets the quota" do
      org_name = "test-org"
      quota_guid = "quota-123"
      org_guid = "org-789"

      create_req_body = { name: org_name }.to_json
      create_response = instance_double("OAuth2::Response", parsed: { "guid" => org_guid }, status: 201)
      quota_response = instance_double("OAuth2::Response", status: 200)

      expect(token_double).to receive(:post)
        .with(
          "https://api.example.com/v3/organizations",
          headers: { "Content-Type" => "application/json" },
          body: create_req_body
        ).and_return(create_response)

      expect(token_double).to receive(:post)
        .with(
          "https://api.example.com/v3/organization_quotas/#{quota_guid}/relationships/organizations",
          headers: { "Content-Type" => "application/json" },
          body: { data: [{ guid: org_guid }] }.to_json
        ).and_return(quota_response)

      result = cf_client.create_organization(org_name, quota_guid)
      expect(result["guid"]).to eq(org_guid)
    end
  end

  describe "#set_space_quota" do
    it "associates a space quota with a space" do
      space_guid = "space-123"
      space_quota_guid = "quota-456"
      expected_body = { data: [{ guid: space_guid }] }.to_json

      response_double = instance_double("OAuth2::Response", status: 200)

      expect(token_double).to receive(:post).with(
        "https://api.example.com/v3/space_quotas/#{space_quota_guid}/relationships/spaces",
        headers: { "Content-Type" => "application/json" },
        body: expected_body
      ).and_return(response_double)

      cf_client.set_space_quota(space_guid, space_quota_guid)
    end
  end

  describe "#add_user_to_space_and_role" do
    it "adds a user to a space with a specific role" do
      user_guid = "user-001"
      space_guid = "space-001"
      role_type = "space_developer"

      expected_body = {
        type: role_type,
        relationships: {
          user: { data: { guid: user_guid } },
          space: { data: { guid: space_guid } }
        }
      }.to_json

      response_double = instance_double("OAuth2::Response", status: 201)

      expect(token_double).to receive(:post).with(
        "https://api.example.com/v3/roles",
        headers: { "Content-Type" => "application/json" },
        body: expected_body
      ).and_return(response_double)

      cf_client.add_user_to_space_and_role(user_guid, space_guid, role_type)
    end
  end

  describe "#add_space_asg" do
    it "associates a security group with a running space" do
      space_guid = "space-xyz"
      asg_name = "my-asg"
      asg_guid = "asg-123"

      asg_response = {
        "resources" => [
          { "guid" => asg_guid }
        ]
      }

      create_req_body = { data: [{ guid: space_guid }] }.to_json
      get_response_double = instance_double("OAuth2::Response", parsed: asg_response)
      post_response_double = instance_double("OAuth2::Response", status: 200)

      expect(token_double).to receive(:get).with(
        "https://api.example.com/v3/security_groups?names=#{CGI.escape(asg_name)}"
      ).and_return(get_response_double)

      expect(token_double).to receive(:post).with(
        "https://api.example.com/v3/security_groups/#{asg_guid}/relationships/running_spaces",
        headers: { "Content-Type" => "application/json" },
        body: create_req_body
      ).and_return(post_response_double)

      result = cf_client.add_space_asg(space_guid, asg_name)
      expect(result.status).to eq(200)
    end
  end

  describe "#create_space" do
    let(:space_name) { "my-space" }
    let(:org_guid) { "org-guid" }
    let(:dev_guid) { "dev-guid" }
    let(:mgr_guid) { "mgr-guid" }
    let(:quota_guid) { "quota-guid" }
    let(:space_guid) { "space-guid" }
    let(:space_response) do
      instance_double("OAuth2::Response", parsed: { "guid" => space_guid }, status: 201)
    end
  
    before do
      # Stub @token.post for space creation
      allow(token_double).to receive(:post)
        .with("https://api.example.com/v3/spaces", anything)
        .and_return(space_response)
  
      # Stub internal method calls that are triggered after space creation
      allow(cf_client).to receive(:set_space_quota)
      allow(cf_client).to receive(:add_user_to_space_and_role)
      allow(cf_client).to receive(:add_space_asg)
    end
  
    it "creates a space and applies quota, roles, and ASGs" do
      cf_client.create_space(space_name, org_guid, dev_guid, mgr_guid, quota_guid)
  
      expect(token_double).to have_received(:post)
        .with("https://api.example.com/v3/spaces", hash_including(
          body: {
            name: space_name,
            relationships: {
              organization: {
                data: { guid: org_guid }
              }
            }
          }.to_json
        ))
  
      expect(cf_client).to have_received(:set_space_quota).with(space_guid, quota_guid)
      expect(cf_client).to have_received(:add_user_to_space_and_role).with(dev_guid, space_guid, "space_developer")
      expect(cf_client).to have_received(:add_user_to_space_and_role).with(mgr_guid, space_guid, "space_manager")
      expect(cf_client).to have_received(:add_space_asg).with(space_guid, "public_networks_egress")
      expect(cf_client).to have_received(:add_space_asg).with(space_guid, "trusted_local_networks_egress")
    end
  end

  describe "#create_organization_space_quota_definition" do
    let(:org_guid) { "test-org-guid" }
    let(:space_name) { "test-space" }
    let(:quota_guid) { "quota-guid-123" }
  
    let(:response_double) do
      instance_double("OAuth2::Response",
        status: 201,
        parsed: { "guid" => quota_guid }
      )
    end
  
    it "creates a space quota definition and returns its details" do
      expected_body = {
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
  
      expect(token_double).to receive(:post)
        .with("https://api.example.com/v3/space_quotas",
          headers: { 'Content-Type' => 'application/json' },
          body: expected_body.to_json)
        .and_return(response_double)
  
      result = cf_client.create_organization_space_quota_definition(org_guid, space_name)
      expect(result["guid"]).to eq(quota_guid)
    end
  end

  describe "#get_org_quota_definition_guid" do
    let(:org_guid) { "org-guid-123" }
  
    it "returns the quota definition guid for the organization" do
      expect(token_double).to receive(:get)
        .with("https://api.example.com/v3/organizations/#{org_guid}")
        .and_return(
          instance_double("OAuth2::Response",
            parsed: {
              "relationships" => {
                "quota" => {
                  "data" => {
                    "guid" => "quota-guid-456"
                  }
                }
              }
            }
          )
        )
  
      result = cf_client.get_org_quota_definition_guid(org_guid)
      expect(result).to eq("quota-guid-456")
    end
  end

  describe "#get_organization_quota" do
    let(:org_guid) { "org-guid-123" }
    let(:quota_guid) { "quota-guid-456" }
  
    before do
      allow(cf_client).to receive(:get_org_quota_definition_guid)
        .with(org_guid)
        .and_return(quota_guid)
    end
  
    it "returns the organization quota details" do
      quota_data = { "guid" => quota_guid, "apps" => {}, "services" => {}, "routes" => {} }
  
      expect(token_double).to receive(:get)
        .with("https://api.example.com/v3/organization_quotas/#{quota_guid}")
        .and_return(instance_double("OAuth2::Response", parsed: quota_data))
  
      result = cf_client.get_organization_quota(org_guid)
      expect(result).to eq(quota_data)
    end
  end


  describe "#increase_org_quota" do
    let(:org) { { "guid" => "org-guid-123", "name" => "test-org" } }
    let(:quota_guid) { "quota-guid-456" }
    let(:spaces) { [{}, {}, {}] } # simulate 3 spaces
    let(:quota_data) do
      {
        "guid" => quota_guid,
        "apps" => { "total_memory_in_mb" => 1024 },
        "services" => { "total_service_instances" => 10 },
        "routes" => { "total_routes" => 10 }
      }
    end
  
    before do
      allow(cf_client).to receive(:get_organization_quota)
        .with(org["guid"])
        .and_return(quota_data)
  
      allow(cf_client).to receive(:get_organization_spaces)
        .with(org["guid"])
        .and_return(spaces)
    end
  
    it "patches the organization quota with updated limits based on space count" do
      expected_body = {
        apps: { total_memory_in_mb: 3072 },
        services: { paid_services_allowed: true, total_service_instances: 30 },
        routes: { total_routes: 30 }
      }
  
      expect(token_double).to receive(:patch)
        .with("https://api.example.com/v3/organization_quotas/#{quota_guid}",
              headers: { 'Content-Type' => 'application/json' },
              body: expected_body.to_json)
        .and_return(instance_double("OAuth2::Response", parsed: quota_data, status: 200))
  
      cf_client.increase_org_quota(org)
    end
  end

  describe "#create_organization_quota" do
    let(:org_name) { "test-org" }
  
    it "creates an organization quota and returns the parsed response" do
      response_body = { "guid" => "quota-guid-123" }
  
      expect(token_double).to receive(:post).with(
        "https://api.example.com/v3/organization_quotas",
        headers: { 'Content-Type' => 'application/json' },
        body: {
          name: org_name,
          apps: { total_memory_in_mb: 1024 },
          services: { paid_services_allowed: false, total_service_instances: 10 },
          routes: { total_routes: 10 }
        }.to_json
      ).and_return(instance_double("OAuth2::Response", parsed: response_body, status: 201))
  
      result = cf_client.create_organization_quota(org_name)
      expect(result).to eq(response_body)
    end
  end

  describe "#get_organization_space_quota_definitions" do
    let(:org_guid) { "org-guid-123" }
  
    it "returns space quota definitions if any exist" do
      parsed_response = {
        "pagination" => { "total_results" => 2 },
        "resources" => [{ "name" => "quota1" }, { "name" => "quota2" }]
      }
  
      expect(token_double).to receive(:get).with(
        "https://api.example.com/v3/space_quotas?organization_guids=#{org_guid}"
      ).and_return(instance_double("OAuth2::Response", parsed: parsed_response))
  
      result = cf_client.get_organization_space_quota_definitions(org_guid)
      expect(result).to eq(parsed_response["resources"])
    end
  
    it "returns nil if no space quotas exist" do
      parsed_response = {
        "pagination" => { "total_results" => 0 },
        "resources" => []
      }
  
      expect(token_double).to receive(:get).with(
        "https://api.example.com/v3/space_quotas?organization_guids=#{org_guid}"
      ).and_return(instance_double("OAuth2::Response", parsed: parsed_response))
  
      result = cf_client.get_organization_space_quota_definitions(org_guid)
      expect(result).to be_nil
    end
  end



  describe "#get_organization_space_quota_definition_by_name" do
    let(:org_guid) { "org-guid-123" }
    let(:target_name) { "quota-match" }
    let(:quotas) do
      [
        { "name" => "quota1" },
        { "name" => "quota-match" },
        { "name" => "quota3" }
      ]
    end
  
    before do
      allow(cf_client).to receive(:get_organization_space_quota_definitions)
        .with(org_guid)
        .and_return(quotas)
    end
  
    it "returns the quota definition that matches the name" do
      result = cf_client.get_organization_space_quota_definition_by_name(org_guid, target_name)
      expect(result).to eq({ "name" => "quota-match" })
    end
  
    it "returns nil if no matching name is found" do
      result = cf_client.get_organization_space_quota_definition_by_name(org_guid, "non-existent")
      expect(result).to be_nil
    end
  end

  describe "#organization_space_name_exists?" do
    let(:org_guid) { "org-guid-123" }
    let(:space_name) { "my-space" }
  
    it "returns true when a space with the given name exists" do
      parsed_response = { "pagination" => { "total_results" => 1 } }
  
      expect(token_double).to receive(:get).with(
        "https://api.example.com/v3/spaces?organization_guids=#{org_guid}&names=#{CGI.escape(space_name)}"
      ).and_return(instance_double("OAuth2::Response", parsed: parsed_response))
  
      result = cf_client.organization_space_name_exists?(org_guid, space_name)
      expect(result).to be true
    end
  
    it "returns false when no space with the given name exists" do
      parsed_response = { "pagination" => { "total_results" => 0 } }
  
      expect(token_double).to receive(:get).with(
        "https://api.example.com/v3/spaces?organization_guids=#{org_guid}&names=#{CGI.escape(space_name)}"
      ).and_return(instance_double("OAuth2::Response", parsed: parsed_response))
  
      result = cf_client.organization_space_name_exists?(org_guid, space_name)
      expect(result).to be false
    end
  end
end