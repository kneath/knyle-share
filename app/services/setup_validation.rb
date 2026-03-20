require "aws-sdk-s3"
require "securerandom"

class SetupValidation
  REQUIRED_ENV_KEYS = %w[
    ADMIN_HOST
    PUBLIC_HOST
    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY
    AWS_REGION
    S3_BUCKET
    GITHUB_CLIENT_ID
    GITHUB_CLIENT_SECRET
  ].freeze

  Check = Data.define(:key, :label, :status, :detail) do
    def passed?
      status == :passed
    end

    def failed?
      status == :failed
    end

    def pending?
      status == :pending
    end

    def css_class
      case status
      when :passed then "check-pass"
      when :failed then "check-fail"
      else "check-pending"
      end
    end

    def icon
      case status
      when :passed then "+"
      when :failed then "!"
      else "?"
      end
    end
  end

  Result = Data.define(:checks) do
    def self.pending
      new(
        checks: [
          Check.new(key: :environment, label: "Environment variables configured", status: :pending, detail: "Run the setup check to validate the current environment."),
          Check.new(key: :database, label: "Database reachable and migrated", status: :pending, detail: "This will confirm the database is reachable and migrations are current."),
          Check.new(key: :s3_config, label: "S3 configuration present", status: :pending, detail: "AWS credentials, region, and bucket name will be checked."),
          Check.new(key: :s3_bucket, label: "S3 bucket reachable", status: :pending, detail: "This confirms the bucket exists and can be reached with the configured credentials."),
          Check.new(key: :s3_round_trip, label: "S3 read/write/delete cycle", status: :pending, detail: "A temporary object will be written, read back, and removed.")
        ]
      )
    end

    def passed?
      checks.all?(&:passed?)
    end

    def pending?
      checks.all?(&:pending?)
    end

    def failed_count
      checks.count(&:failed?)
    end

    def passed_count
      checks.count(&:passed?)
    end

    def summary
      return "Run validation to verify your configuration before claiming the admin account." if pending?
      return "All #{checks.count} checks passed. Continue to GitHub to claim the admin account." if passed?

      "#{failed_count} of #{checks.count} checks failed. Fix the issues above and re-run."
    end
  end

  def initialize(env: ENV, database_connection: ActiveRecord::Base.connection, migration_context: ActiveRecord::Base.connection_pool.migration_context, s3_client: nil)
    @env = env
    @database_connection = database_connection
    @migration_context = migration_context
    @s3_client = s3_client
  end

  def call
    environment_check = validate_environment
    database_check = validate_database
    s3_config_check = validate_s3_config
    s3_bucket_check = validate_s3_bucket(s3_config_check.passed?)
    s3_round_trip_check = validate_s3_round_trip(s3_bucket_check.passed?)

    Result.new(checks: [environment_check, database_check, s3_config_check, s3_bucket_check, s3_round_trip_check])
  end

  private

  attr_reader :env, :database_connection, :migration_context

  def validate_environment
    missing = REQUIRED_ENV_KEYS.select { |key| env[key].blank? }
    detail = if missing.empty?
      "All required variables are present."
    else
      "Missing: #{missing.join(', ')}"
    end

    build_check(:environment, "Environment variables configured", missing.empty?, detail)
  end

  def validate_database
    database_connection.execute("SELECT 1")

    if migration_context.needs_migration?
      build_check(:database, "Database reachable and migrated", false, "Pending migrations are present.")
    else
      build_check(:database, "Database reachable and migrated", true, "Database connection is healthy and migrations are current.")
    end
  rescue StandardError => error
    build_check(:database, "Database reachable and migrated", false, error.message)
  end

  def validate_s3_config
    required = %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION S3_BUCKET]
    missing = required.select { |key| env[key].blank? }
    detail = if missing.empty?
      "AWS credentials, region, and bucket are configured."
    else
      "Missing: #{missing.join(', ')}"
    end

    build_check(:s3_config, "S3 configuration present", missing.empty?, detail)
  end

  def validate_s3_bucket(config_present)
    unless config_present
      return build_check(:s3_bucket, "S3 bucket reachable", false, "Skipped until S3 configuration is complete.")
    end

    client.head_bucket(bucket: env.fetch("S3_BUCKET"))
    build_check(:s3_bucket, "S3 bucket reachable", true, "The configured bucket is reachable.")
  rescue StandardError => error
    build_check(:s3_bucket, "S3 bucket reachable", false, error.message)
  end

  def validate_s3_round_trip(bucket_reachable)
    unless bucket_reachable
      return build_check(:s3_round_trip, "S3 read/write/delete cycle", false, "Skipped until bucket access is working.")
    end

    key = "setup-validation/#{SecureRandom.uuid}.txt"
    body = "knyle-share-setup-check"

    client.put_object(bucket: env.fetch("S3_BUCKET"), key:, body:)

    response_body = client.get_object(bucket: env.fetch("S3_BUCKET"), key:).body.read
    raise "Uploaded object could not be read back." unless response_body == body

    client.delete_object(bucket: env.fetch("S3_BUCKET"), key:)

    build_check(:s3_round_trip, "S3 read/write/delete cycle", true, "Temporary object write, read, and delete succeeded.")
  rescue StandardError => error
    build_check(:s3_round_trip, "S3 read/write/delete cycle", false, error.message)
  end

  def build_check(key, label, passed, detail)
    Check.new(key:, label:, status: passed ? :passed : :failed, detail:)
  end

  def client
    @client ||= begin
      @s3_client || Aws::S3::Client.new(
        access_key_id: env.fetch("AWS_ACCESS_KEY_ID"),
        secret_access_key: env.fetch("AWS_SECRET_ACCESS_KEY"),
        region: env.fetch("AWS_REGION")
      )
    end
  end
end
