class BundleSubdomainStatic
  DEFAULT_STATIC_PREFIXES_ON_BUNDLE_HOST = ["/app-assets/"].freeze

  def initialize(app, path, index: "index", headers: {}, static_prefixes_on_bundle_host: DEFAULT_STATIC_PREFIXES_ON_BUNDLE_HOST)
    @app = app
    @static = ActionDispatch::Static.new(app, path, index:, headers:)
    @static_prefixes_on_bundle_host = static_prefixes_on_bundle_host
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    if PublicBundleRouting.bundle_host?(host: request.host, public_host: public_host) &&
       !serve_static_on_bundle_host?(request.path)
      return @app.call(env)
    end

    @static.call(env)
  end

  private

  attr_reader :static_prefixes_on_bundle_host

  def public_host
    ENV.fetch("PUBLIC_HOST", "share.lvh.me")
  end

  def serve_static_on_bundle_host?(path)
    static_prefixes_on_bundle_host.any? { |prefix| path.start_with?(prefix) }
  end
end
