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
        copy_source: "#{bucket}/#{source_key}",
        key: destination_key,
        metadata_directive: "COPY"
      )
    end

    def read(key:)
      client.get_object(bucket:, key:).body.read
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
        expires_in:
      )
    end

    def delete(key:)
      client.delete_object(bucket:, key:)
    end

    private

    attr_reader :bucket, :env

    def client
      @client ||= @s3_client || Aws::S3::Client.new(**AwsClientOptions.s3(env:))
    end
  end
end
