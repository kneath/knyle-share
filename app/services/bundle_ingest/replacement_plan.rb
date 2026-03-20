module BundleIngest
  ReplacementPlan = Data.define(
    :bundle_id,
    :slug,
    :current_content_revision,
    :next_content_revision,
    :current_access_revision,
    :next_access_revision,
    :replace_existing,
    :preserves_analytics,
    :preserves_sessions,
    :preserves_signed_links,
    :published_storage_prefix
  ) do
    def replacing_existing?
      replace_existing
    end
  end
end
