class BundleSubdomainStatic
  def initialize(app, path, index: "index", headers: {})
    @app = app
    @static = ActionDispatch::Static.new(app, path, index:, headers:)
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    return @app.call(env) if PublicBundleRouting.bundle_host?(host: request.host, public_host: public_host)

    @static.call(env)
  end

  private

  def public_host
    ENV.fetch("PUBLIC_HOST", "share.lvh.me")
  end
end
