require "aws-sdk-s3"
require "rack/mime"

module BundleIngest
  class ObjectStore
    StoredObject = Data.define(:key, :content_type, :byte_size, :checksum)

    def initialize(bucket: ENV.fetch("S3_BUCKET"), s3_client: nil, env: ENV)
      @bucket = bucket
      @s3_client = s3_client
      @env = env
    end

    def list(prefix:)
      objects = []
      continuation_token = nil

      loop do
        response = client.list_objects_v2(
          bucket:,
          prefix:,
          continuation_token:
        )

        response.contents.each do |object|
          next if object.key.end_with?("/")

          objects << StoredObject.new(
            key: object.key,
            content_type: Rack::Mime.mime_type(File.extname(object.key), "application/octet-stream"),
            byte_size: object.size,
            checksum: object.etag.to_s.delete('"').presence
          )
        end

        break unless response.is_truncated

        continuation_token = response.next_continuation_token
      end

      objects
    end

    def copy(source_key:, destination_key:)
      client.copy_object(
        bucket:,
        # CopySource is a URL path, so keys need escaping (as Aws::S3::Object#copy_from does).
        copy_source: "#{bucket}/#{Seahorse::Util.uri_path_escape(source_key)}",
        key: destination_key,
        metadata_directive: "COPY"
      )
    end

    def read(key:)
      client.get_object(bucket:, key:).body.read
    end

    # Streams the object to a local file instead of holding it in memory.
    def download(key:, to:)
      client.get_object(bucket:, key:, response_target: to)
      to
    end

    def write(key:, body:, content_type:)
      client.put_object(
        bucket:,
        key:,
        body:,
        content_type:
      )
    end

    def presign_put(key:, content_type:, expires_in: 15.minutes)
      Aws::S3::Presigner.new(client:).presigned_url(
        :put_object,
        bucket:,
        key:,
        content_type:,
        expires_in: expires_in.to_i
      )
    end

    def delete(key:)
      client.delete_object(bucket:, key:)
    end

    DELETE_BATCH_SIZE = 1_000

    # One DeleteObjects request per 1,000 keys instead of one request each.
    def delete_many(keys:)
      keys.each_slice(DELETE_BATCH_SIZE) do |batch|
        response = client.delete_objects(bucket:, delete: { objects: batch.map { |key| { key: } }, quiet: true })
        next if response.errors.blank?

        failed = response.errors.map { |error| "#{error.key} (#{error.code})" }
        raise Aws::S3::Errors::ServiceError.new(nil, "Could not delete #{failed.size} object(s): #{failed.first(5).join(', ')}")
      end
    end

    private

    attr_reader :bucket, :env

    def client
      @client ||= @s3_client || Aws::S3::Client.new(**AwsClientOptions.s3(env:))
    end
  end
end
