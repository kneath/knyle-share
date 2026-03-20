require "pathname"

module BundleIngest
  class PublishedStorageKey
    class InvalidPathError < StandardError; end

    def self.call(path:, bundle: nil, bundle_id: nil, content_revision: nil)
      new(bundle:, bundle_id:, content_revision:, path:).call
    end

    def initialize(bundle:, bundle_id:, content_revision:, path:)
      @bundle = bundle
      @bundle_id = bundle_id
      @content_revision = content_revision
      @path = path
    end

    def call
      "bundles/#{resolved_bundle_id}/#{resolved_content_revision}/#{normalized_path}"
    end

    private

    attr_reader :bundle, :bundle_id, :content_revision, :path

    def resolved_bundle_id
      bundle_id || bundle&.id || raise(ArgumentError, "bundle_id is required")
    end

    def resolved_content_revision
      content_revision || bundle&.content_revision || raise(ArgumentError, "content_revision is required")
    end

    def normalized_path
      value = path.to_s.sub(/\A\.\//, "").sub(/\A\//, "")
      raise InvalidPathError, "Path cannot be blank." if value.blank?
      raise InvalidPathError, "Path traversal is not allowed." if value.include?("..")

      Pathname.new(value).cleanpath.to_s
    end
  end
end
