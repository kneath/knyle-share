require "uri"
require "cgi"

module PublicBundleRouting
  module_function

  def bundle_url(bundle:, public_host:, base_url:, access_token: nil)
    build_url(
      base_url:,
      host: host_for(bundle:, public_host:),
      path: bundle_path,
      query: query_for(access_token:)
    )
  end

  def access_url(bundle:, public_host:, base_url:)
    build_url(
      base_url:,
      host: host_for(bundle:, public_host:),
      path: access_path
    )
  end

  def download_url(bundle:, public_host:, base_url:, access_token: nil)
    build_url(
      base_url:,
      host: host_for(bundle:, public_host:),
      path: download_path,
      query: query_for(access_token:)
    )
  end

  def raw_url(bundle:, public_host:, base_url:, access_token: nil)
    build_url(
      base_url:,
      host: host_for(bundle:, public_host:),
      path: raw_path,
      query: query_for(access_token:)
    )
  end

  def asset_url(bundle:, asset_path:, public_host:, base_url:, access_token: nil)
    build_url(
      base_url:,
      host: host_for(bundle:, public_host:),
      path: bundle_asset_path(bundle:, asset_path:),
      query: query_for(access_token:)
    )
  end

  def host_for(bundle:, public_host:)
    bundle_host_for(slug: bundle.slug, public_host:)
  end

  def bundle_host_for(slug:, public_host:)
    "#{slug}.#{normalize_host(public_host)}"
  end

  def bundle_host?(host:, public_host:)
    slug_from_host(host:, public_host:).present?
  end

  def slug_from_host(host:, public_host:)
    normalized_host = host.to_s.downcase
    normalized_public_host = normalize_host(public_host)
    suffix = ".#{normalized_public_host}"

    return if normalized_host.blank? || normalized_host == normalized_public_host
    return unless normalized_host.end_with?(suffix)

    slug = normalized_host.delete_suffix(suffix)
    return if slug.blank? || slug.include?(".")

    slug
  end

  def bundle_path
    "/"
  end

  def access_path
    "/access"
  end

  def download_path
    "/download"
  end

  def raw_path
    "/raw"
  end

  def bundle_asset_path(bundle:, asset_path:)
    normalized_asset_path = asset_path.to_s.sub(%r{\A/+}, "")
    "/#{normalized_asset_path}"
  end

  def query_for(access_token:)
    access_token.present? ? { access: access_token }.to_query : nil
  end

  def build_url(base_url:, host:, path:, query: nil)
    uri = URI.parse(base_url.to_s)
    uri.host = host
    uri.path = encode_path(path)
    uri.query = query.presence
    uri.to_s
  end

  def normalize_host(host)
    host.to_s.downcase.sub(/\A\.+/, "").sub(/\.+\z/, "")
  end

  def encode_path(path)
    path.to_s.split("/", -1).map { |segment| CGI.escape(segment).gsub("+", "%20") }.join("/")
  end
end
