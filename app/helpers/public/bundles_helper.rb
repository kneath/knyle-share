module Public
  module BundlesHelper
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
