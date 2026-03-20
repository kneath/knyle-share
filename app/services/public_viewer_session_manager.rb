require "digest"
require "securerandom"

class PublicViewerSessionManager
  COOKIE_PREFIX = "bundle_access".freeze

  def initialize(cookies:)
    @cookies = cookies
  end

  def find(bundle:)
    raw_token = cookies.signed[cookie_name(bundle)]
    return if raw_token.blank?

    viewer_session = bundle.viewer_sessions.find_by(token_digest: digest(raw_token))
    return clear(bundle) if viewer_session.blank? || viewer_session.expires_at <= Time.current

    viewer_session
  end

  def establish!(bundle:, expires_at: nil)
    raw_token = SecureRandom.urlsafe_base64(32)
    expires_at ||= bundle_expiry(bundle)

    viewer_session = bundle.viewer_sessions.create!(
      token_digest: digest(raw_token),
      expires_at:,
      last_seen_at: Time.current
    )

    write_cookie(bundle:, raw_token:, expires_at:)
    viewer_session
  end

  def refresh!(bundle:, viewer_session:, expires_at: nil)
    expires_at ||= bundle_expiry(bundle)
    raw_token = cookies.signed[cookie_name(bundle)]

    viewer_session.update!(expires_at:, last_seen_at: Time.current)
    write_cookie(bundle:, raw_token:, expires_at:) if raw_token.present?
    viewer_session
  end

  private

  attr_reader :cookies

  def clear(bundle)
    cookies.delete(cookie_name(bundle), path: cookie_path(bundle))
    nil
  end

  def cookie_name(bundle)
    "#{COOKIE_PREFIX}_#{bundle.id}"
  end

  def cookie_path(bundle)
    "/#{bundle.slug}"
  end

  def digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def write_cookie(bundle:, raw_token:, expires_at:)
    cookies.signed[cookie_name(bundle)] = {
      value: raw_token,
      httponly: true,
      same_site: :lax,
      expires: expires_at,
      path: cookie_path(bundle)
    }
  end

  def bundle_expiry(bundle)
    Time.current + bundle.password_session_ttl_seconds.seconds
  end
end
