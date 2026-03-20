require "aws-sdk-s3"

class BundleStorage
  MissingObjectError = Class.new(StandardError)
  DEFAULT_PUBLIC_ASSET_REDIRECT_TTL_SECONDS = 5.minutes.to_i
  DEFAULT_INLINE_MARKDOWN_RENDER_MAX_BYTES = 1.megabyte.to_i

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

  def download_url(asset, disposition:, expires_in: public_asset_redirect_ttl_seconds)
    Aws::S3::Presigner.new(client:).presigned_url(
      :get_object,
      bucket:,
      key: asset.storage_key,
      response_content_type: asset.content_type,
      response_content_disposition: content_disposition_for(asset:, disposition:),
      expires_in: expires_in.to_i
    )
  end

  def render_markdown_inline?(asset)
    asset.byte_size <= inline_markdown_render_max_bytes
  end

  private

  attr_reader :bucket, :env

  def client
    @client ||= @s3_client || Aws::S3::Client.new(**AwsClientOptions.s3(env:))
  end

  def content_disposition_for(asset:, disposition:)
    ActionDispatch::Http::ContentDisposition.format(
      disposition:,
      filename: File.basename(asset.path)
    )
  end

  def public_asset_redirect_ttl_seconds
    Integer(env.fetch("PUBLIC_ASSET_REDIRECT_TTL_SECONDS", DEFAULT_PUBLIC_ASSET_REDIRECT_TTL_SECONDS))
  rescue ArgumentError, TypeError
    DEFAULT_PUBLIC_ASSET_REDIRECT_TTL_SECONDS
  end

  def inline_markdown_render_max_bytes
    Integer(env.fetch("INLINE_MARKDOWN_RENDER_MAX_BYTES", DEFAULT_INLINE_MARKDOWN_RENDER_MAX_BYTES))
  rescue ArgumentError, TypeError
    DEFAULT_INLINE_MARKDOWN_RENDER_MAX_BYTES
  end
end
