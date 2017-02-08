module MonitorHelper
  def is_valid_email(username)
    !username.nil? && !username.index("@").nil?
  end

  def is_whitelisted_email(email)
    email.end_with?('.gov', '.mil')
  end

  def get_sandbox_space_name(email)
    return email.downcase
  end

  def get_cloud_environment(uaa_url)
    environment = 'unknown'
    if (uaa_url.index("uaa."))
      environment = uaa_url[uaa_url.index("uaa.")+4..-1]
    end

    environment
  end
end
