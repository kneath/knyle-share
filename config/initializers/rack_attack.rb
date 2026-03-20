class Rack::Attack
  admin_host = ENV.fetch("ADMIN_HOST", "admin.lvh.me")

  throttle("api-by-ip", limit: 300, period: 5.minutes) do |request|
    request.ip if request.host == admin_host && request.path.start_with?("/api/v1/")
  end

  throttle("bundle-password-by-ip", limit: 10, period: 5.minutes) do |request|
    request.ip if request.post? && request.path.match?(%r{\A/[^/]+/access\z})
  end

  self.throttled_responder = lambda do |request|
    if request.path.start_with?("/api/v1/")
      [429, { "Content-Type" => "application/json" }, [{ error: "Rate limit exceeded" }.to_json]]
    else
      [429, { "Content-Type" => "text/plain" }, ["Rate limit exceeded"]]
    end
  end
end
