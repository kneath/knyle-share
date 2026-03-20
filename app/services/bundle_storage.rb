require "aws-sdk-s3"
require "action_dispatch/http/content_disposition"

class BundleStorage
  MissingObjectError = Class.new(StandardError)
  DEFAULT_PUBLIC_ASSET_REDIRECT_TTL_SECONDS = 5.minutes.to_i
  DEFAULT_PUBLIC_ASSET_RESPONSE_CACHE_CONTROL = "public, max-age=31536000, immutable"
  DEFAULT_PROTECTED_ASSET_RESPONSE_CACHE_CONTROL = "private, no-store"
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

  def download_url(asset, disposition:, expires_in: public_asset_redirect_ttl_seconds, response_cache_control: nil)
    params = {
      bucket:,
      key: asset.storage_key,
      response_content_type: asset.content_type,
      response_content_disposition: content_disposition_for(asset:, disposition:),
      expires_in: expires_in.to_i
    }
    params[:response_cache_control] = response_cache_control if response_cache_control.present?

    Aws::S3::Presigner.new(client:).presigned_url(:get_object, **params)
  end

  def render_markdown_inline?(asset)
    asset.byte_size <= inline_markdown_render_max_bytes
  end

  def public_asset_response_cache_control
    env.fetch("PUBLIC_ASSET_RESPONSE_CACHE_CONTROL", DEFAULT_PUBLIC_ASSET_RESPONSE_CACHE_CONTROL)
  end

  def protected_asset_response_cache_control
    env.fetch("PROTECTED_ASSET_RESPONSE_CACHE_CONTROL", DEFAULT_PROTECTED_ASSET_RESPONSE_CACHE_CONTROL)
  end

  def public_asset_redirect_ttl_seconds
    Integer(env.fetch("PUBLIC_ASSET_REDIRECT_TTL_SECONDS", DEFAULT_PUBLIC_ASSET_REDIRECT_TTL_SECONDS))
  rescue ArgumentError, TypeError
    DEFAULT_PUBLIC_ASSET_REDIRECT_TTL_SECONDS
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

  def inline_markdown_render_max_bytes
    Integer(env.fetch("INLINE_MARKDOWN_RENDER_MAX_BYTES", DEFAULT_INLINE_MARKDOWN_RENDER_MAX_BYTES))
  rescue ArgumentError, TypeError
    DEFAULT_INLINE_MARKDOWN_RENDER_MAX_BYTES
  end
end
