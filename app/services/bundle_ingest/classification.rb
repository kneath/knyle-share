require "pathname"

module BundleIngest
  Classification = Data.define(:presentation_kind, :source_kind, :entry_path, :paths) do
    def static_site?
      presentation_kind == "static_site"
    end

    def markdown_document?
      presentation_kind == "markdown_document"
    end

    def single_download?
      presentation_kind == "single_download"
    end

    def file_listing?
      presentation_kind == "file_listing"
    end
  end
end
