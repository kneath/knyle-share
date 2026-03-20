module Public
  class BaseController < ApplicationController
    PUBLIC_DOCUMENT_CACHE_TTL_SECONDS = 5.minutes.to_i
    PUBLIC_DOCUMENT_EDGE_CACHE_TTL_SECONDS = 5.minutes.to_i
    PUBLIC_DOCUMENT_STALE_WHILE_REVALIDATE_SECONDS = 1.minute.to_i
    BUNDLE_PAGE_CACHE_VERSION = 1

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
      return unless stale_bundle_page?(asset:, variant: :static_site_html)

      fetched_asset = fetch_bundle_asset(asset)
      record_bundle_view(
        bundle: @bundle,
        viewer_session:,
        access_method:,
        request_path: request.path
      )

      render html: fetched_asset.fetch(:body).html_safe, layout: false, content_type: fetched_asset.fetch(:content_type)
    end

    def send_asset(asset, disposition:)
      response.set_header("Referrer-Policy", "no-referrer")
      response.set_header("Cache-Control", bundle_asset_redirect_cache_control)
      response.set_header("Pragma", "no-cache") unless @bundle.public_access?

      redirect_to(
        storage.download_url(
          asset,
          disposition:,
          expires_in: storage.public_asset_redirect_ttl_seconds,
          response_cache_control: bundle_asset_response_cache_control
        ),
        allow_other_host: true
      )
    end

    def bundle_slug
      slug = params[:slug].presence || PublicBundleRouting.slug_from_host(host: request.host, public_host:)
      raise ActiveRecord::RecordNotFound, "Bundle not found" if slug.blank?

      slug
    end

    def stale_bundle_page?(asset: nil, variant:, extra: nil)
      stale?(
        etag: bundle_page_cache_key(asset:, variant:, extra:),
        last_modified: bundle_page_last_modified(asset:),
        public: @bundle.public_access?,
        cache_control: bundle_page_cache_control
      )
    end

    def bundle_page_cache_key(asset:, variant:, extra:)
      [
        "bundle-page",
        BUNDLE_PAGE_CACHE_VERSION,
        variant,
        extra,
        @bundle.id,
        @bundle.content_revision,
        @bundle.access_revision,
        @bundle.access_mode,
        @bundle.status,
        asset&.id,
        asset&.checksum,
        asset&.rendered_html_version,
        asset&.byte_size,
        asset&.content_type
      ]
    end

    def bundle_page_last_modified(asset:)
      [asset&.updated_at, @bundle.last_replaced_at, @bundle.updated_at, @bundle.created_at].compact.max
    end

    def bundle_page_cache_control
      if @bundle.public_access?
        {
          max_age: PUBLIC_DOCUMENT_CACHE_TTL_SECONDS,
          stale_while_revalidate: PUBLIC_DOCUMENT_STALE_WHILE_REVALIDATE_SECONDS,
          extras: [ "s-maxage=#{PUBLIC_DOCUMENT_EDGE_CACHE_TTL_SECONDS}" ]
        }
      else
        {
          no_cache: true,
          must_revalidate: true,
          extras: [ "private" ]
        }
      end
    end

    def bundle_asset_redirect_cache_control
      if @bundle.public_access?
        "public, max-age=#{storage.public_asset_redirect_ttl_seconds}"
      else
        "private, no-store"
      end
    end

    def bundle_asset_response_cache_control
      if @bundle.public_access?
        storage.public_asset_response_cache_control
      else
        storage.protected_asset_response_cache_control
      end
    end

    def fetch_bundle_asset(asset)
      measure_server_timing("bundle-storage-read") { storage.fetch(asset) }
    end

    def read_bundle_asset(asset)
      measure_server_timing("bundle-storage-read") { storage.read(asset) }
    end

    def record_bundle_view(bundle:, viewer_session:, access_method:, request_path:)
      measure_server_timing("bundle-analytics-enqueue") do
        analytics.record_view_later(
          bundle:,
          viewer_session:,
          access_method:,
          request_path:
        )
      end
    end

    def measure_server_timing(metric)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      if started_at
        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0
        append_server_timing(metric, duration_ms)
      end
    end

    def append_server_timing(metric, duration_ms)
      entry = "#{metric};dur=#{format('%.2f', duration_ms)}"
      existing = response.get_header("Server-Timing")
      response.set_header("Server-Timing", [existing, entry].compact.join(", "))
    end
  end
end
