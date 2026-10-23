# POST-only, with omniauth-rails_csrf_protection verifying the token, so other
# sites can't start a GitHub sign-in with a plain link (CVE-2015-9284).
OmniAuth.config.allowed_request_methods = %i[post]

Rails.application.config.middleware.use OmniAuth::Builder do
  provider(
    :github,
    ENV.fetch("GITHUB_CLIENT_ID", "placeholder-client-id"),
    ENV.fetch("GITHUB_CLIENT_SECRET", "placeholder-client-secret"),
    scope: "read:user"
  )
end
