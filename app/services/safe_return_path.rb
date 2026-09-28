class SafeReturnPath
  def self.call(value, fallback: "/")
    path = value.to_s
    return fallback unless path.start_with?("/") && !path.start_with?("//")
    return fallback if path.match?(/[\\\x00-\x20]/) || path.match?(/%2f|%5c|%0[ad]/i)
    uri = URI.parse(path)
    uri.host.nil? && uri.scheme.nil? ? path : fallback
  rescue URI::InvalidURIError
    fallback
  end
end
