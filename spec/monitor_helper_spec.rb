require_relative '../monitor_helper'
require 'spec_helper'

describe MonitorHelper do

	let(:monitor_helper_test) { Class.new { extend MonitorHelper} }

	it "should validate user email" do

		expect(monitor_helper_test.is_valid_email('test')).to be false
		expect(monitor_helper_test.is_valid_email('michael.barnicle@gsa.gov')).to be true
		expect(monitor_helper_test.is_valid_email('')).to be false
		expect(monitor_helper_test.is_valid_email(nil)).to be false

	end

	it "should validate allowlisted emails" do

		expect(monitor_helper_test.is_allowlisted_email('test@gsa.gov')).to be true
		expect(monitor_helper_test.is_allowlisted_email('test@domain.mil')).to be true
		expect(monitor_helper_test.is_allowlisted_email('test@si.edu')).to be true
		expect(monitor_helper_test.is_allowlisted_email('test@domain.com')).to be false

	end

	it "should return top level org from email address" do

		expect(monitor_helper_test.get_email_domain_name('test@some.domain.gov')).to eq 'domain'

	end

	it "should return the correct org from an email address" do
		expect(monitor_helper_test.get_email_domain_name('foobar@DOMAIN.GOV')).to eq 'domain'
		expect(monitor_helper_test.get_email_domain_name('foobar@DOMAIN.FED.US')).to eq 'domain'
		expect(monitor_helper_test.get_email_domain_name('foobar@DOMAIN.MIL')).to eq 'domain'
	end

	it "should return the correct sandbox org name" do
		expect(monitor_helper_test.get_sandbox_org_name('foo@test.gov')).to eq 'sandbox-test'
	end

	it "should extract a valid sandbox space name from email" do

		expect(monitor_helper_test.get_sandbox_space_name('john.doe@some.domain.gov')).to eq 'john.doe'
		expect(monitor_helper_test.get_sandbox_space_name('John.Doe@some.domain.gov')).to eq 'john.doe'

	end

	it "should extract the environment from the uaa url" do

		expect(monitor_helper_test.get_cloud_environment('https://uaa.cloud.gov')).to eq 'cloud.gov'
		expect(monitor_helper_test.get_cloud_environment('https://uaa.fr.cloud.gov')).to eq 'fr.cloud.gov'
		expect(monitor_helper_test.get_cloud_environment('https://bad.url')).to eq 'unknown'

	end


end
