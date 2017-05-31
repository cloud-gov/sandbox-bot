require 'csv'

module MonitorHelper

  if ENV['DOMAIN_CSV_PATH']
    @@domains = CSV.read(ENV['DOMAIN_CSV_PATH'], headers: true).map do |row|
      row['Domain Name'].downcase
    end
  else
    @@domains = ['.gov', '.mil']
  end

	def is_valid_email(username)

		!username.nil? && !username.index("@").nil?

	end

	def is_whitelisted_email(email)

    @@domains.any? do |domain|
      email.downcase.end_with?(domain)
    end

	end

	# Extracts the domain name (minus the top level domain) from
	# an email address. e.g. foo@subdomain.domain.org = domain

	def get_email_domain_name(email)

    domain = email.split('@')[1]
    domain.split('.')[-2]

	end

	def get_sandbox_space_name(email)

   		return email.split('@')[0].downcase

	end

	def get_cloud_environment(uaa_url)

		environment = 'unknown'
		if (uaa_url.index("uaa."))
			environment = uaa_url[uaa_url.index("uaa.")+4..-1]
		end

		environment

	end

end
