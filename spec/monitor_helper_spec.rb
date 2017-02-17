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

	it "should validate whitelisted emails" do

		expect(monitor_helper_test.is_whitelisted_email('test@domain.gov')).to be true
		expect(monitor_helper_test.is_whitelisted_email('test@domain.mil')).to be true
		expect(monitor_helper_test.is_whitelisted_email('test@domain.com')).to be false

	end

	it "should return top level org from email address" do

		expect(monitor_helper_test.get_email_domain_name('test@some.domain.gov')).to eq 'domain'

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
