OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true

Rails.application.config.middleware.use OmniAuth::Builder do
  provider(
    :github,
    ENV.fetch("GITHUB_CLIENT_ID", "placeholder-client-id"),
    ENV.fetch("GITHUB_CLIENT_SECRET", "placeholder-client-secret"),
    scope: "read:user"
  )
end
