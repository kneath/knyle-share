class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :admin_host, :public_host, :public_bundle_url_for, :public_bundle_access_url_for, :public_bundle_asset_url_for, :public_bundle_download_url_for, :public_bundle_raw_url_for

  private

  def admin_host
    ENV.fetch("ADMIN_HOST", "admin.lvh.me")
  end

  def public_host
    ENV.fetch("PUBLIC_HOST", "share.lvh.me")
  end

  def public_bundle_url_for(bundle, access_token: nil)
    PublicBundleRouting.bundle_url(
      bundle:,
      public_host:,
      base_url: request.base_url,
      access_token:
    )
  end

  def public_bundle_access_url_for(bundle)
    PublicBundleRouting.access_url(
      bundle:,
      public_host:,
      base_url: request.base_url
    )
  end

  def public_bundle_asset_url_for(bundle, asset_path:, access_token: nil)
    PublicBundleRouting.asset_url(
      bundle:,
      asset_path:,
      public_host:,
      base_url: request.base_url,
      access_token:
    )
  end

  def public_bundle_download_url_for(bundle, access_token: nil)
    PublicBundleRouting.download_url(
      bundle:,
      public_host:,
      base_url: request.base_url,
      access_token:
    )
  end

  def public_bundle_raw_url_for(bundle, access_token: nil)
    PublicBundleRouting.raw_url(
      bundle:,
      public_host:,
      base_url: request.base_url,
      access_token:
    )
  end
end
