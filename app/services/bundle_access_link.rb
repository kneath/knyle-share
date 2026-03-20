class BundleAccessLink
  PURPOSE = "bundle_access_link".freeze
  PRESETS = {
    "1_day" => { label: "1 day", duration: 1.day },
    "1_week" => { label: "1 week", duration: 1.week },
    "1_month" => { label: "1 month", duration: 1.month }
  }.freeze

  def self.generate(bundle:, expires_in:)
    expires_at = Time.current + expires_in
    verifier.generate({ bundle_id: bundle.id, slug: bundle.slug, expires_at: expires_at.iso8601 }, expires_in:, purpose: PURPOSE)
  end

  def self.verify(token)
    payload = verifier.verified(token, purpose: PURPOSE)
    return if payload.blank?

    {
      bundle_id: payload[:bundle_id] || payload["bundle_id"],
      slug: payload[:slug] || payload["slug"],
      expires_at: Time.iso8601(payload[:expires_at] || payload["expires_at"])
    }
  end

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
