# Neither Render nor Cloudflare needs X-Forwarded-Host, but Rails prefers it
# over Host when it's present. A client could send one to make a bundle
# subdomain route as a different bundle, and a cache keyed on the real Host
# would then store the wrong response. Drop it before anything reads the host.
class StripForwardedHost
  def initialize(app)
    @app = app
  end

  def call(env)
    env.delete("HTTP_X_FORWARDED_HOST")
    @app.call(env)
  end
end
