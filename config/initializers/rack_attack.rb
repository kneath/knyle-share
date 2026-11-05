class Rack::Attack
  class Request < ::Rack::Request
    # Rack::Attack runs after ActionDispatch::RemoteIp, which resolves the real
    # client behind Cloudflare. request.ip would be the Cloudflare edge.
    def client_ip
      env["action_dispatch.remote_ip"]&.to_s.presence || ip
    end

    # One IPv6 client usually controls a whole /64, so throttle the /64
    # rather than each address in it.
    def client_key
      address = IPAddr.new(client_ip)
      address.ipv6? && !address.ipv4_mapped? ? "#{address.mask(64)}/64" : client_ip
    rescue IPAddr::InvalidAddressError
      client_ip
    end

    # The slug a password POST targets, from the bundle subdomain or the
    # legacy /:slug/access path. Nil for every other request.
    def bundle_password_slug
      return unless post?

      public_host = ENV.fetch("PUBLIC_HOST", "share.lvh.me")
      if path == "/access" && PublicBundleRouting.bundle_host?(host:, public_host:)
        PublicBundleRouting.slug_from_host(host:, public_host:)
      elsif host == public_host
        path[%r{\A/([^/]+)/access\z}, 1]
      end
    end
  end

  admin_host = ENV.fetch("ADMIN_HOST", "admin.lvh.me")

  throttle("api-by-ip", limit: 300, period: 5.minutes) do |request|
    request.client_key if request.host == admin_host && request.path.start_with?("/api/v1/")
  end

  throttle("bundle-password-by-ip", limit: 10, period: 5.minutes) do |request|
    request.client_key if request.bundle_password_slug
  end

  # Caps guesses against one bundle from any number of addresses. While it
  # trips, the password form for that bundle returns 429 for everyone;
  # signed links and existing viewer sessions keep working.
  throttle("bundle-password-by-slug", limit: 50, period: 1.hour) do |request|
    request.bundle_password_slug
  end

  self.throttled_responder = lambda do |request|
    if request.path.start_with?("/api/v1/")
      [429, { "Content-Type" => "application/json" }, [{ error: "Rate limit exceeded" }.to_json]]
    else
      retry_after = request.env.dig("rack.attack.match_data", :period) || 5.minutes
      [429, { "Content-Type" => "text/html; charset=utf-8", "Retry-After" => retry_after.to_i.to_s }, [File.read(Rails.root.join("public/429.html"))]]
    end
  end
end
