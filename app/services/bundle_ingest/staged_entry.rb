module BundleIngest
  StagedEntry = Data.define(:path, :source_key, :content_type, :byte_size, :checksum, :body)
end
