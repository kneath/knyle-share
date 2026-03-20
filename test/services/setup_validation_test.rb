require "test_helper"
require "stringio"

class SetupValidationTest < ActiveSupport::TestCase
  FakeMigrationContext = Struct.new(:needs_migration?)

  class FakeS3Client
    attr_reader :objects

    def initialize(head_bucket_error: nil)
      @head_bucket_error = head_bucket_error
      @objects = {}
    end

    def head_bucket(bucket:)
      raise @head_bucket_error if @head_bucket_error

      bucket
    end

    def put_object(bucket:, key:, body:)
      objects[[bucket, key]] = body
    end

    def get_object(bucket:, key:)
      Struct.new(:body).new(StringIO.new(objects.fetch([bucket, key])))
    end

    def delete_object(bucket:, key:)
      objects.delete([bucket, key])
    end
  end

  class FakeConnection
    def initialize(error: nil)
      @error = error
    end

    def execute(_sql)
      raise @error if @error

      true
    end
  end

  test "passes when environment database and s3 checks succeed" do
    result = SetupValidation.new(
      env: required_env,
      database_connection: FakeConnection.new,
      migration_context: FakeMigrationContext.new(false),
      s3_client: FakeS3Client.new
    ).call

    assert_predicate result, :passed?
    assert_equal 5, result.passed_count
  end

  test "reports missing configuration and pending migrations" do
    env = required_env.except("S3_BUCKET", "GITHUB_CLIENT_SECRET")

    result = SetupValidation.new(
      env:,
      database_connection: FakeConnection.new,
      migration_context: FakeMigrationContext.new(true),
      s3_client: FakeS3Client.new
    ).call

    assert_not result.passed?
    assert_includes result.checks.find { |check| check.key == :environment }.detail, "GITHUB_CLIENT_SECRET"
    assert_includes result.checks.find { |check| check.key == :database }.detail, "Pending migrations"
    assert_includes result.checks.find { |check| check.key == :s3_config }.detail, "S3_BUCKET"
  end

  private

  def required_env
    {
      "ADMIN_HOST" => "admin.lvh.me",
      "PUBLIC_HOST" => "share.lvh.me",
      "AWS_ACCESS_KEY_ID" => "key",
      "AWS_SECRET_ACCESS_KEY" => "secret",
      "AWS_REGION" => "us-west-2",
      "S3_BUCKET" => "bucket",
      "GITHUB_CLIENT_ID" => "client-id",
      "GITHUB_CLIENT_SECRET" => "client-secret"
    }
  end
end
