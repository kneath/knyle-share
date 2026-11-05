# Production names the session cookie __Host-knyle_share_session so a bundle
# subdomain can't plant one for the admin host (see config/application.rb).
host_cookie_prefix = Rails.application.config.x.host_cookie_prefix

Rails.application.config.session_store :cookie_store,
  key: host_cookie_prefix.present? ? "#{host_cookie_prefix}knyle_share_session" : "_knyle_share_session"
