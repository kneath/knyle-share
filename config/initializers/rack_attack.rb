class Rack::Attack
  admin_host = ENV.fetch("ADMIN_HOST", "admin.lvh.me")

  throttle("api-by-ip", limit: 300, period: 5.minutes) do |request|
    request.ip if request.host == admin_host && request.path.start_with?("/api/v1/")
  end

  throttle("bundle-password-by-ip", limit: 10, period: 5.minutes) do |request|
    public_host = ENV.fetch("PUBLIC_HOST", "share.lvh.me")
    canonical = PublicBundleRouting.bundle_host?(host: request.host, public_host:) && request.path == "/access"
    legacy = request.host == public_host && request.path.match?(%r{\A/[^/]+/access\z})
    request.ip if request.post? && (canonical || legacy)
  end

  self.throttled_responder = lambda do |request|
    if request.path.start_with?("/api/v1/")
      [429, { "Content-Type" => "application/json" }, [{ error: "Rate limit exceeded" }.to_json]]
    else
      [429, { "Content-Type" => "text/html; charset=utf-8", "Retry-After" => "300" }, [File.read(Rails.root.join("public/429.html"))]]
    end
  end
end
