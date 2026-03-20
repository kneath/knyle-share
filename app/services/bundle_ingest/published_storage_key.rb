require "pathname"

module BundleIngest
  class PublishedStorageKey
    class InvalidPathError < StandardError; end

    def self.call(bundle:, path:)
      new(bundle:, path:).call
    end

    def initialize(bundle:, path:)
      @bundle = bundle
      @path = path
    end

    def call
      "bundles/#{bundle.id}/#{bundle.content_revision}/#{normalized_path}"
    end

    private

    attr_reader :bundle, :path

    def normalized_path
      value = path.to_s.sub(/\A\.\//, "").sub(/\A\//, "")
      raise InvalidPathError, "Path cannot be blank." if value.blank?
      raise InvalidPathError, "Path traversal is not allowed." if value.include?("..")

      Pathname.new(value).cleanpath.to_s
    end
  end
end
