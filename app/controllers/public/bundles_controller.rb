module Public
  class BundlesController < BaseController
    skip_forgery_protection only: :asset

    FILE_LISTING_PAGE_SIZE = 50
    INVALID_FILE_LISTING_PREFIX = :invalid

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

          record_bundle_view(
            bundle: @bundle,
            viewer_session: result.viewer_session,
            access_method: result.access_method,
            request_path: request.path
          )

          @rendered_markdown =
            if @entry_asset.has_prerendered_markdown?
              @entry_asset.rendered_html
            else
              markdown_body = read_bundle_asset(@entry_asset)
              measure_server_timing("bundle-markdown-render") do
                BundleMarkdownRenderer.render(markdown_body)
              end
            end
          render :markdown
        else
          return unless stale_bundle_page?(asset: @entry_asset, variant: :markdown_download)

          record_bundle_view(
            bundle: @bundle,
            viewer_session: result.viewer_session,
            access_method: result.access_method,
            request_path: request.path
          )
          render :markdown_download
        end
      when "single_download"
        @entry_asset = entry_asset

        if displayable_image?(@entry_asset)
          return unless stale_bundle_page?(asset: @entry_asset, variant: :image_display)

          record_bundle_view(
            bundle: @bundle,
            viewer_session: result.viewer_session,
            access_method: result.access_method,
            request_path: request.path
          )

          @image_url = inline_asset_url(@entry_asset)
          render :image_display

        elsif displayable_video?(@entry_asset)
          return unless stale_bundle_page?(asset: @entry_asset, variant: :video_display)

          record_bundle_view(
            bundle: @bundle,
            viewer_session: result.viewer_session,
            access_method: result.access_method,
            request_path: request.path
          )

          @video_url = inline_asset_url(@entry_asset)
          render :video_display
        else
          return unless stale_bundle_page?(asset: @entry_asset, variant: :single_download)

          record_bundle_view(
            bundle: @bundle,
            viewer_session: result.viewer_session,
            access_method: result.access_method,
            request_path: request.path
          )
          render :single_download
        end
      when "file_listing"
        @current_file_listing_prefix = requested_file_listing_prefix
        if @current_file_listing_prefix == INVALID_FILE_LISTING_PREFIX
          render plain: "Directory not found.", status: :not_found
          return
        end

        @page = requested_page
        @per_page = FILE_LISTING_PAGE_SIZE
        @total_file_listing_entries = BundleAsset.file_listing_entry_count_for(
          bundle: @bundle,
          prefix: @current_file_listing_prefix
        )
        if @current_file_listing_prefix.present? && @total_file_listing_entries.zero?
          render plain: "Directory not found.", status: :not_found
          return
        end

        @total_file_listing_pages = [(@total_file_listing_entries.to_f / @per_page).ceil, 1].max
        @current_file_listing_page = [@page, @total_file_listing_pages].min
        @file_listing_entries = BundleAsset.file_listing_entries_for(
          bundle: @bundle,
          prefix: @current_file_listing_prefix,
          limit: @per_page,
          offset: (@current_file_listing_page - 1) * @per_page
        )

        return unless stale_bundle_page?(
          variant: :file_listing,
          extra: [@current_file_listing_prefix, @total_file_listing_entries, @current_file_listing_page, @per_page]
        )

        record_bundle_view(
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

    DISPLAYABLE_IMAGE_CONTENT_TYPES = %w[
      image/jpeg image/png image/gif image/webp image/svg+xml
    ].freeze

    DISPLAYABLE_VIDEO_CONTENT_TYPES = %w[
      video/mp4 video/webm video/quicktime
    ].freeze

    def displayable_image?(asset)
      DISPLAYABLE_IMAGE_CONTENT_TYPES.include?(asset.content_type)
    end

    def displayable_video?(asset)
      DISPLAYABLE_VIDEO_CONTENT_TYPES.include?(asset.content_type)
    end

    def inline_asset_url(asset)
      storage.download_url(
        asset,
        disposition: "inline",
        expires_in: storage.public_asset_redirect_ttl_seconds,
        response_cache_control: bundle_asset_response_cache_control
      )
    end

    def requested_asset_path
      [params[:asset_path], params[:format]].compact.join(".")
    end

    def requested_page
      page = params[:page].to_i
      page.positive? ? page : 1
    end

    def requested_file_listing_prefix
      raw_prefix = params[:prefix].to_s
      return "" if raw_prefix.blank?

      segments = raw_prefix.split("/").reject(&:blank?)
      return INVALID_FILE_LISTING_PREFIX if segments.any? { |segment| %w[. ..].include?(segment) }

      "#{segments.join('/')}/"
    end

    def ensure_protected_static_asset_request_is_same_origin!
      return unless @bundle.static_site? && @bundle.protected_access?

      fetch_site = request.get_header("HTTP_SEC_FETCH_SITE").to_s
      return if %w[same-origin none].include?(fetch_site)

      render plain: "Bundle asset not found.", status: :not_found
    end
  end
end
