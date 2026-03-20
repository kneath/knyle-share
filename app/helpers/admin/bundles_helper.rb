module Admin
  module BundlesHelper
    def bundle_last_viewed_label(bundle)
      return "Never viewed" if bundle.last_viewed_at.blank?

      time_ago_in_words(bundle.last_viewed_at) + " ago"
    end

    def bundle_created_label(bundle)
      bundle.created_at ? bundle.created_at.strftime("%b %-d, %Y") : "Unknown"
    end

    def bundle_last_replaced_label(bundle)
      return "Never" if bundle.last_replaced_at.blank?

      bundle.last_replaced_at.strftime("%b %-d, %Y")
    end

    def bundle_size_label(bundle)
      number_to_human_size(bundle.byte_size)
    end

    def bundle_views_label(bundle)
      pluralize(bundle.total_views_count, "view")
    end

    def bundle_unique_viewers_label(bundle)
      return "n/a" if bundle.public_access?

      pluralize(bundle.unique_protected_viewers_count, "viewer")
    end
  end
end
