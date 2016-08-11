module MonitorHelper

	def is_valid_email(username)

		!username.nil? && !username.index("@").nil?

	end

	def is_whitelisted_email(email)

		email.end_with?('.gov', '.mil')

	end

	# Extracts the domain name (minus the top level domain) from
	# an email address. e.g. foo@subdomain.domain.org = domain

	def get_email_domain_name(email)

    	domain = email.split('@')[1]
    	top_level_domain = domain.split('.')[-2]

	end

	def get_sandbox_space_name(email)

   		return email.split('@')[0].downcase

	end

	# Checks to see if a user sandbox space already exists
	# in the parent org epaces

	def user_space_exists(user_space_name, org_spaces)

		org_spaces.each do |org_space|
			if org_space["entity"]["name"] == user_space_name
				return true
			end
		end

		return false

	end


end
