require "aws-sdk-s3"

class BundleStorage
  MissingObjectError = Class.new(StandardError)

  def initialize(bucket: ENV.fetch("S3_BUCKET"), s3_client: nil, env: ENV)
    @bucket = bucket
    @s3_client = s3_client
    @env = env
  end

  def read(asset)
    response = client.get_object(bucket:, key: asset.storage_key)
    response.body.read
  rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound => error
    raise MissingObjectError, error.message
  end

  def fetch(asset)
    {
      body: read(asset),
      content_type: asset.content_type,
      filename: File.basename(asset.path)
    }
  end

  private

  attr_reader :bucket, :env

  def client
    @client ||= @s3_client || Aws::S3::Client.new(**AwsClientOptions.s3(env:))
  end
end
