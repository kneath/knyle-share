module BundleIngest
  class ReplacementPlanner
    def self.call(bundle:, replace_existing:)
      new(bundle:, replace_existing:).call
    end

    def initialize(bundle:, replace_existing:)
      @bundle = bundle
      @replace_existing = replace_existing
    end

    def call
      ReplacementPlan.new(
        bundle_id: bundle.id,
        slug: bundle.slug,
        current_content_revision: bundle.content_revision,
        next_content_revision: bundle.content_revision + 1,
        current_access_revision: bundle.access_revision,
        next_access_revision: bundle.access_revision + 1,
        replace_existing: replace_existing,
        preserves_analytics: true,
        preserves_sessions: false,
        preserves_signed_links: false,
        published_storage_prefix: "bundles/#{bundle.id}/#{bundle.content_revision + 1}"
      )
    end

    private

    attr_reader :bundle, :replace_existing
  end
end
