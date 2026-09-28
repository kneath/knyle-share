class MemoryObjectStore
  attr_reader :objects, :deleted
  attr_accessor :fail_writes, :fail_deletes, :before_copy

  def initialize
    @objects = {}
    @deleted = []
  end

  def write(key:, body:, content_type:)
    raise IOError, "Storage temporarily unavailable" if fail_writes
    @objects[key] = { body: body.respond_to?(:read) ? body.read : body, content_type: }
  end

  def presign_put(key:, content_type:, **)
    "http://admin.lvh.me:4010/unavailable-direct-upload"
  end

  def read(key:)
    @objects.fetch(key).fetch(:body)
  end

  def copy(source_key:, destination_key:)
    before_copy&.call
    raise IOError, "Storage temporarily unavailable" if fail_writes
    @objects[destination_key] = @objects.fetch(source_key).dup
  end

  def list(prefix:)
    objects.filter_map do |key, value|
      if key.start_with?(prefix)
        BundleIngest::ObjectStore::StoredObject.new(key:, content_type: value[:content_type], byte_size: value[:body].bytesize, checksum: nil)
      end
    end
  end

  def delete(key:)
    raise IOError, "Storage temporarily unavailable" if fail_deletes
    deleted << key
    objects.delete(key)
  end
end
