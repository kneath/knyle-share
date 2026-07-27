require_relative "../../lib/knyle_share/tls_defaults"

module AwsClientOptions
  module_function

  def s3(env: ENV)
    {
      access_key_id: env.fetch("AWS_ACCESS_KEY_ID"),
      secret_access_key: env.fetch("AWS_SECRET_ACCESS_KEY"),
      region: env.fetch("AWS_REGION"),
      ssl_ca_store: ssl_ca_store
    }.compact
  end

  def ssl_ca_store
    KnyleShare::TlsDefaults.ssl_ca_store
  end
end
