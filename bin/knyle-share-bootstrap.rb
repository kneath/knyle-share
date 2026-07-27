require "rubygems"

module KnyleShareBootstrap
  REQUIRED_RUBY_VERSION = "3.2"

  module_function

  def ensure_supported_ruby!(ruby_version = RUBY_VERSION, stderr = $stderr)
    return if Gem::Version.new(ruby_version) >= Gem::Version.new(REQUIRED_RUBY_VERSION)

    stderr.puts(
      "knyle-share requires Ruby #{REQUIRED_RUBY_VERSION} or newer, " \
      "but found Ruby #{ruby_version}. Install the CLI with a supported Ruby " \
      "(`gem install knyle-share`) or select Ruby #{REQUIRED_RUBY_VERSION}+ " \
      "with a version manager."
    )
    exit 1
  end

  def setup!(script_file, ruby_version = RUBY_VERSION, stderr = $stderr)
    ensure_supported_ruby!(ruby_version, stderr)

    script_path = File.realpath(script_file)
    repo_root = File.expand_path("..", File.dirname(script_path))
    ENV["BUNDLE_GEMFILE"] ||= File.join(repo_root, "Gemfile")

    begin
      require "bundler/setup"
    rescue LoadError => error
      dependency_error!(error, stderr)
    rescue StandardError => error
      raise unless defined?(Bundler::BundlerError) && error.is_a?(Bundler::BundlerError)

      dependency_error!(error, stderr)
    end

    $LOAD_PATH.unshift(File.join(repo_root, "lib"))
    repo_root
  end

  def dependency_error!(error, stderr)
    stderr.puts(
      "Could not load the knyle-share dependencies (#{error.message}). " \
      "Run `bin/setup` or `bundle install` in the knyle-share checkout."
    )
    exit 1
  end
end
