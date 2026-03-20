module Public
  class BaseController < ApplicationController
    private

    def set_bundle
      @bundle = Bundle.find_by!(slug: bundle_slug)
    end

    def entry_asset
      @entry_asset ||= @bundle.assets.find_by!(path: @bundle.entry_path)
    end

    def access_result
      @access_result ||= PublicBundleAccess.new(bundle: @bundle, cookies:, params:).call
    end

    def viewer_session_manager
      @viewer_session_manager ||= PublicViewerSessionManager.new(cookies:)
    end

    def analytics
      @analytics ||= PublicBundleAnalytics.new
    end

    def storage
      @storage ||= BundleStorage.new
    end

    def ensure_bundle_is_available!
      return true unless @bundle.disabled?

      render "public/bundles/unavailable", status: :gone
      false
    end

    def ensure_bundle_access!(allow_password_gate: false)
      return unless ensure_bundle_is_available!

      result = access_result
      return result if result.allowed?

      if allow_password_gate
        @access_message = result.message
        render "public/bundles/protected", status: result.message.present? ? :unauthorized : :ok
      else
        redirect_to public_bundle_url_for(@bundle), alert: result.message.presence || "This bundle is protected.", allow_other_host: true
      end

      nil
    end

    def ensure_bundle_host!(url:)
      expected_host = PublicBundleRouting.host_for(bundle: @bundle, public_host:)
      return true if request.host.downcase == expected_host

      redirect_to url, allow_other_host: true
      false
    end

    def render_html_asset(asset, access_method:, viewer_session: nil)
      fetched_asset = storage.fetch(asset)
      analytics.record_view!(
        bundle: @bundle,
        viewer_session:,
        access_method:,
        request_path: request.path
      )

      render html: fetched_asset.fetch(:body).html_safe, layout: false, content_type: fetched_asset.fetch(:content_type)
    end

    def send_asset(asset, disposition:)
      response.set_header("Referrer-Policy", "no-referrer")
      redirect_to storage.download_url(asset, disposition:), allow_other_host: true
    end

    def bundle_slug
      slug = params[:slug].presence || PublicBundleRouting.slug_from_host(host: request.host, public_host:)
      raise ActiveRecord::RecordNotFound, "Bundle not found" if slug.blank?

      slug
    end
  end
end
