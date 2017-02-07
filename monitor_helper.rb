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
end
