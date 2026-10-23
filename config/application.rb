require_relative "boot"
require_relative "../lib/public_bundle_routing"
require_relative "../lib/bundle_subdomain_static"
require_relative "../lib/host_constraint"
require_relative "../lib/bundle_subdomain_host_constraint"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module KnyleShare
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # lib/knyle_share is the standalone CLI library: it ships as a gem, manages
    # its own require graph, and uses gem naming conventions (KnyleShare::VERSION)
    # that Zeitwerk would misread. The app reaches it only through explicit
    # require_relative calls.
    config.autoload_lib(ignore: %w[assets tasks knyle_share knyle_share.rb])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.assets.prefix = "/app-assets"

    # Production sits behind Cloudflare, so the connecting IP Render sees is a
    # Cloudflare edge. Trusting Cloudflare's published ranges lets
    # request.remote_ip resolve to the real client from X-Forwarded-For, while
    # requests that bypass Cloudflare can't spoof it.
    # Ranges from https://www.cloudflare.com/ips/
    config.action_dispatch.trusted_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES + %w[
      173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
      141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
      197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
      104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
      2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32
      2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
    ].map { |range| IPAddr.new(range) }
  end
end
