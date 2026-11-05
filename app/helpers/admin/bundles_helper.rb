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
      pluralize(bundle.total_views_count, "recorded view")
    end

    # One status dot: a disabled bundle reads as disabled whatever its access.
    def bundle_status_tag(bundle)
      if bundle.disabled?
        tag.span(bundle.status_label, class: "status status-disabled")
      else
        tag.span(bundle.access_label, class: "status status-#{bundle.access_mode}")
      end
    end

    def bundle_updated_label(bundle)
      return "" if bundle.updated_at.blank?
      return "Just now" if bundle.updated_at > 1.minute.ago
      return time_ago_in_words(bundle.updated_at).delete_prefix("about ").capitalize + " ago" if bundle.updated_at > 1.week.ago

      bundle.updated_at.strftime(bundle.updated_at.year == Time.current.year ? "%b %-d" : "%b %-d, %Y")
    end

    BUNDLE_SORTS = { "name" => "ascending", "views" => "descending", "updated" => "descending", "newest" => "descending" }.freeze

    def bundle_sort_header(label, sort, css: nil)
      current = BUNDLE_SORTS.key?(params[:sort]) ? params[:sort] : "updated"
      link = link_to(label, admin_bundles_path(request.query_parameters.merge("sort" => sort).except("page")))
      tag.th(link, scope: "col", class: css, aria: { sort: (BUNDLE_SORTS[sort] if current == sort) })
    end

    def bundle_unique_viewers_label(bundle)
      return "n/a" if bundle.public_access?

      pluralize(bundle.unique_protected_viewers_count, "session")
    end
  end
end
