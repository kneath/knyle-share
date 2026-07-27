require "openssl"
require "rbconfig"
require "rubygems"

module KnyleShare
  module TlsDefaults
    module_function

    def ssl_ca_store
      return unless darwin_openssl_36_workaround?

      store = OpenSSL::X509::Store.new
      store.set_default_paths

      # Ruby 3.4.2 + OpenSSL 3.6.0 on macOS can fail HTTPS handshakes with
      # "unable to get certificate CRL" / "OCSP verification failed" even when
      # the peer certificate chain is otherwise valid. Using a custom store with
      # default trust roots and neutral verify flags avoids that regression while
      # keeping normal certificate verification enabled.
      store.flags = 0
      store
    end

    def darwin_openssl_36_workaround?
      RbConfig::CONFIG["host_os"].include?("darwin") &&
        Gem::Version.new(openssl_version) >= Gem::Version.new("3.6.0")
    end

    def openssl_version
      version_string = OpenSSL::OPENSSL_LIBRARY_VERSION rescue OpenSSL::OPENSSL_VERSION
      version_string[/\d+\.\d+\.\d+/] || "0.0.0"
    end
  end
end
