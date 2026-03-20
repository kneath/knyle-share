class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :admin_host, :public_host

  private

  def admin_host
    ENV.fetch("ADMIN_HOST", "admin.lvh.me")
  end

  def public_host
    ENV.fetch("PUBLIC_HOST", "share.lvh.me")
  end
end
