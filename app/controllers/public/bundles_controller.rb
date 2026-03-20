module Public
  class BundlesController < BaseController
    skip_forgery_protection only: :asset

    FILE_LISTING_PAGE_SIZE = 50

    before_action :set_bundle
    before_action :ensure_protected_static_asset_request_is_same_origin!, only: :asset

    def show
      return unless ensure_bundle_host!(url: public_bundle_url_for(@bundle, access_token: params[:access]))

      result = ensure_bundle_access!(allow_password_gate: true)
      return unless result

      case @bundle.presentation_kind
      when "static_site"
        render_html_asset(entry_asset, access_method: result.access_method, viewer_session: result.viewer_session)
      when "markdown_document"
        @entry_asset = entry_asset
        if storage.render_markdown_inline?(@entry_asset)
          return unless stale_bundle_page?(asset: @entry_asset, variant: :markdown_inline)

          analytics.record_view!(
            bundle: @bundle,
            viewer_session: result.viewer_session,
            access_method: result.access_method,
            request_path: request.path
          )

          @rendered_markdown = helpers.sanitize(Commonmarker.to_html(storage.read(@entry_asset)))
          render :markdown
        else
          return unless stale_bundle_page?(asset: @entry_asset, variant: :markdown_download)

          analytics.record_view!(
            bundle: @bundle,
            viewer_session: result.viewer_session,
            access_method: result.access_method,
            request_path: request.path
          )
          render :markdown_download
        end
      when "single_download"
        @entry_asset = entry_asset
        return unless stale_bundle_page?(asset: @entry_asset, variant: :single_download)

        analytics.record_view!(
          bundle: @bundle,
          viewer_session: result.viewer_session,
          access_method: result.access_method,
          request_path: request.path
        )
        render :single_download
      when "file_listing"
        @page = requested_page
        @per_page = FILE_LISTING_PAGE_SIZE
        @total_file_listing_pages = [(@bundle.asset_count.to_f / @per_page).ceil, 1].max
        @current_file_listing_page = [@page, @total_file_listing_pages].min
        @file_listing_assets = @bundle.assets
          .select(:id, :path, :byte_size)
          .order(:path)
          .offset((@current_file_listing_page - 1) * @per_page)
          .limit(@per_page)

        return unless stale_bundle_page?(
          variant: :file_listing,
          extra: [@bundle.asset_count, @bundle.byte_size, @current_file_listing_page, @per_page]
        )

        analytics.record_view!(
          bundle: @bundle,
          viewer_session: result.viewer_session,
          access_method: result.access_method,
          request_path: request.path
        )

        render :file_listing
      else
        render plain: "Unsupported bundle presentation", status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotFound, BundleStorage::MissingObjectError
      render plain: "Bundle asset not found.", status: :not_found
    end

    def raw
      return unless ensure_bundle_host!(url: public_bundle_raw_url_for(@bundle, access_token: params[:access]))

      result = ensure_bundle_access!
      return unless result

      unless @bundle.presentation_kind == "markdown_document"
        render plain: "Raw markdown is only available for Markdown bundles.", status: :not_found
        return
      end

      send_asset(entry_asset, disposition: "inline")
    rescue ActiveRecord::RecordNotFound, BundleStorage::MissingObjectError
      render plain: "Bundle asset not found.", status: :not_found
    end

    def download
      return unless ensure_bundle_host!(url: public_bundle_download_url_for(@bundle, access_token: params[:access]))

      result = ensure_bundle_access!
      return unless result

      unless %w[markdown_document single_download].include?(@bundle.presentation_kind)
        render plain: "Download is not available for this bundle.", status: :not_found
        return
      end

      send_asset(entry_asset, disposition: "attachment")
    rescue ActiveRecord::RecordNotFound, BundleStorage::MissingObjectError
      render plain: "Bundle asset not found.", status: :not_found
    end

    def asset
      return unless ensure_bundle_host!(url: public_bundle_asset_url_for(@bundle, asset_path: requested_asset_path, access_token: params[:access]))

      result = ensure_bundle_access!
      return unless result

      unless %w[static_site file_listing].include?(@bundle.presentation_kind)
        render plain: "Nested asset paths are not available for this bundle.", status: :not_found
        return
      end

      asset = @bundle.assets.find_by!(path: requested_asset_path)

      if @bundle.presentation_kind == "static_site" && asset.content_type == "text/html"
        render_html_asset(asset, access_method: result.access_method, viewer_session: result.viewer_session)
      else
        send_asset(asset, disposition: @bundle.presentation_kind == "file_listing" ? "attachment" : "inline")
      end
    rescue ActiveRecord::RecordNotFound, BundleStorage::MissingObjectError
      render plain: "Bundle asset not found.", status: :not_found
    end

    private

    def requested_asset_path
      [params[:asset_path], params[:format]].compact.join(".")
    end

    def requested_page
      page = params[:page].to_i
      page.positive? ? page : 1
    end

    def ensure_protected_static_asset_request_is_same_origin!
      return unless @bundle.static_site? && @bundle.protected_access?

      fetch_site = request.get_header("HTTP_SEC_FETCH_SITE").to_s
      return if %w[same-origin none].include?(fetch_site)

      render plain: "Bundle asset not found.", status: :not_found
    end
  end
end
