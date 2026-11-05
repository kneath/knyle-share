module BundleIngest
  # A file to publish: either an object already in S3 (source_key) or one
  # extracted to local disk from an uploaded archive (local_path).
  StagedEntry = Data.define(:path, :source_key, :content_type, :byte_size, :checksum, :local_path)
end
