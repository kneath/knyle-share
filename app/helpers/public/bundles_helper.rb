module Public
  module BundlesHelper
    def public_bundle_size_label(bytes)
      number_to_human_size(bytes)
    end

    def public_bundle_file_name(asset)
      File.basename(asset.path)
    end
  end
end
