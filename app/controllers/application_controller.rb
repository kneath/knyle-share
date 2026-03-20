class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :admin_host, :public_host, :public_bundle_url_for

  private

  def admin_host
    ENV.fetch("ADMIN_HOST", "admin.lvh.me")
  end

  def public_host
    ENV.fetch("PUBLIC_HOST", "share.lvh.me")
  end

  def public_bundle_url_for(bundle, access_token: nil)
    uri = URI.parse(request.base_url)
    uri.host = public_host
    uri.path = "/#{bundle.slug}"
    uri.query = access_token.present? ? { access: access_token }.to_query : nil
    uri.to_s
  end
end
