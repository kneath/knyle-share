module Public
  module BundlesHelper
    def viewer_endpoint(action, asset = @entry_asset)
      query = { path: asset.path }
      query[:access] = params[:access] if params[:access].present?
      "/_share/#{action}?#{query.to_query}"
    end

    def asset_download_url(bundle = @bundle, asset = @entry_asset)
      if bundle.presentation_kind == "file_listing"
        public_bundle_asset_url_for(bundle, asset_path: asset.path, access_token: params[:access])
      else
        public_bundle_download_url_for(bundle, access_token: params[:access])
      end
    end

    def public_bundle_size_label(bytes)
      number_to_human_size(bytes)
    end

    def public_bundle_file_name(asset)
      File.basename(asset.path)
    end

    def public_bundle_file_listing_url_for(bundle, access_token: nil, prefix: nil, page: nil)
      query = {}
      query[:access] = access_token if access_token.present?
      query[:prefix] = prefix if prefix.present?
      query[:page] = page if page.to_i > 1

      base_url = public_bundle_url_for(bundle)
      query.any? ? "#{base_url}?#{query.to_query}" : base_url
    end

    def public_bundle_file_listing_breadcrumbs(prefix)
      breadcrumbs = [ { label: "All files", prefix: nil } ]
      current_prefix = +""

      prefix.to_s.split("/").reject(&:blank?).each do |segment|
        current_prefix << "#{segment}/"
        breadcrumbs << { label: segment, prefix: current_prefix.dup }
      end

      breadcrumbs
    end
  end
end
