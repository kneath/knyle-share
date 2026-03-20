require "io/console"
require "json"
require "optparse"

module KnyleShare
  class CLI
    LINK_PRESETS = {
      "1_day" => "1 day",
      "1_week" => "1 week",
      "1_month" => "1 month"
    }.freeze

    def initialize(stdin: $stdin, stdout: $stdout, stderr: $stderr, env: ENV, config_store: ConfigStore.new(env: ENV))
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @env = env
      @config_store = config_store
    end

    def run(argv)
      @json_errors = false
      command = argv.first

      return run_login(argv.drop(1)) if command == "login"
      return print_usage if command.nil? || %w[-h --help help].include?(command)
      return run_share(argv.drop(1)) if command == "share"

      run_share(argv)
    rescue OptionParser::ParseError => error
      emit_error(error.message)
      1
    rescue Error, ApiError => error
      emit_error(error.message)
      1
    rescue Interrupt
      emit_error("Canceled.")
      130
    end

    private

    attr_reader :stdin, :stdout, :stderr, :env, :config_store

    def run_login(argv)
      options = { admin_url: nil, api_token: nil }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: knyle-share login [options]"
        opts.on("--admin-url URL", "Admin base URL, for example https://admin.example.com") { |value| options[:admin_url] = value }
        opts.on("--token TOKEN", "API token from the admin UI") { |value| options[:api_token] = value }
      end

      parser.parse!(argv)

      admin_url = options[:admin_url] || prompt_for_value("Admin URL")
      api_token = options[:api_token] || prompt_for_secret("API token")

      client = Client.new(admin_url:, api_token:)
      client.availability(slug: "knyle-share-auth-check")

      config_path = config_store.save(admin_url:, api_token:)
      stdout.puts "Saved CLI configuration to #{config_path}."
      stdout.puts "The token was verified against #{admin_url}."
      0
    end

    def run_share(argv)
      options = {
        slug: nil,
        replace: false,
        access_mode: nil,
        password: nil,
        generate_password: false,
        confirm_upload: true,
        json: false,
        admin_url: nil,
        api_token: nil,
        link_expiration: nil
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: knyle-share <path> [options]"
        opts.on("--slug SLUG", "Bundle slug") { |value| options[:slug] = value }
        opts.on("--replace", "Replace an existing bundle without prompting") { options[:replace] = true }
        opts.on("--public", "Publish as a public bundle") { options[:access_mode] = "public" }
        opts.on("--protected", "Publish as a protected bundle") { options[:access_mode] = "protected" }
        opts.on("--password PASSWORD", "Custom password for a protected bundle") { |value| options[:password] = value }
        opts.on("--generate-password", "Generate a three-word password for a protected bundle") { options[:generate_password] = true }
        opts.on("--link-expiration PRESET", LINK_PRESETS.keys, "Generate an expiring link: #{LINK_PRESETS.keys.join(', ')}") do |value|
          options[:link_expiration] = value
        end
        opts.on("--yes", "Skip the final upload confirmation") { options[:confirm_upload] = false }
        opts.on("--json", "Print machine-readable JSON output") { options[:json] = true }
        opts.on("--admin-url URL", "Admin base URL override") { |value| options[:admin_url] = value }
        opts.on("--token TOKEN", "API token override") { |value| options[:api_token] = value }
      end

      parser.parse!(argv)
      @json_errors = options[:json]
      path = argv.shift
      raise Error, parser.banner if path.to_s.strip.empty?
      raise Error, "Unexpected arguments: #{argv.join(' ')}" if argv.any?

      validate_share_options!(options)

      configuration = config_store.load
      admin_url = options[:admin_url] || configuration[:admin_url]
      api_token = options[:api_token] || configuration[:api_token]
      raise Error, "Missing CLI configuration. Run `bin/knyle-share login` or set KNYLE_SHARE_ADMIN_URL and KNYLE_SHARE_API_TOKEN." if blank?(admin_url) || blank?(api_token)

      client = Client.new(admin_url:, api_token:)
      source = UploadSource.prepare(path)

      result =
        begin
          bundle_slug, replace_existing = resolve_slug(
            client:,
            initial_slug: options[:slug] || default_slug_for(path),
            replace_existing: options[:replace],
            interactive: interactive?(options)
          )
          access_mode = resolve_access_mode(options)
          password = resolve_password(options, access_mode:, interactive: interactive?(options))

          confirm_share!(
            source:,
            slug: bundle_slug,
            access_mode:,
            replace_existing:,
            password:,
            interactive: interactive?(options),
            skip_confirmation: !options[:confirm_upload]
          )

          say "Creating upload…" unless options[:json]
          upload = client.create_upload(
            slug: bundle_slug,
            source_kind: source.source_kind,
            original_filename: source.original_filename,
            access_mode:,
            replace_existing:,
            password:
          )

          say "Uploading bundle…" unless options[:json]
          client.put_file(
            upload_url: upload.fetch("upload_url"),
            file_path: source.upload_path,
            content_type: source.content_type
          )

          say "Publishing bundle…" unless options[:json]
          client.finalize_upload(id: upload.fetch("id"), byte_size: source.byte_size)
          process_result = client.process_upload(id: upload.fetch("id"))
          bundle = process_result.fetch("bundle")

          response = {
            "slug" => bundle.fetch("slug"),
            "share_url" => bundle.fetch("public_url"),
            "presentation_kind" => bundle.fetch("presentation_kind"),
            "content_revision" => bundle.fetch("content_revision"),
            "access_mode" => access_mode
          }
          response["password"] = password if password

          if options[:link_expiration]
            raise Error, "Expiring links only apply to protected bundles." unless access_mode == "protected"

            link = client.create_link(slug: bundle_slug, expires_in: options[:link_expiration])
            response["signed_url"] = link.fetch("url")
            response["signed_url_expires_at"] = link.fetch("expires_at")
          end

          if options[:json]
            stdout.puts JSON.pretty_generate(response)
          else
            print_share_summary(response)
            prompt_next_action(client:, response:) if interactive?(options)
          end

          response
        ensure
          source.cleanup
        end

      result ? 0 : 1
    end

    def validate_share_options!(options)
      if options[:password] && options[:generate_password]
        raise Error, "Use either --password or --generate-password, not both."
      end

      if options[:access_mode] == "public" && (options[:password] || options[:generate_password])
        raise Error, "Passwords only apply to protected bundles."
      end
    end

    def resolve_slug(client:, initial_slug:, replace_existing:, interactive:)
      slug = initial_slug

      loop do
        availability = client.availability(slug:)

        return [ slug, replace_existing ] if availability["available"]

        if availability["exists"] && availability["replaceable"]
          return [ slug, true ] if replace_existing

          if interactive
            if confirm("Bundle #{slug} already exists. Replace it?", default: false)
              return [ slug, true ]
            end

            slug = prompt_for_value("Bundle slug", default: next_slug_candidate(slug))
            next
          end

          raise Error, "Bundle #{slug} already exists. Re-run with --replace or choose a different --slug."
        end

        if availability["reserved"]
          raise Error, "Bundle slug #{slug} is reserved." unless interactive

          slug = prompt_for_value("Bundle slug", default: next_slug_candidate(slug))
          next
        end

        raise Error, "Bundle slug #{slug} is not available."
      end
    end

    def resolve_access_mode(options)
      access_mode = options[:access_mode]
      access_mode ||= "protected" if options[:password] || options[:generate_password] || options[:link_expiration]

      return access_mode if access_mode
      raise Error, "Access mode is required when stdin is not interactive." unless interactive?(options)

      choice = prompt_for_value("Access mode (public/protected)", default: "protected")
      normalized = choice.downcase
      return normalized if %w[public protected].include?(normalized)

      raise Error, "Access mode must be public or protected."
    end

    def resolve_password(options, access_mode:, interactive:)
      return nil if access_mode == "public"
      return options[:password] if options[:password]
      return PasswordGenerator.generate if options[:generate_password]

      raise Error, "Protected uploads require --password or --generate-password when stdin is not interactive." unless interactive

      strategy = prompt_for_value("Password strategy (generated/custom)", default: "generated").downcase

      case strategy
      when "generated"
        password = PasswordGenerator.generate
        say "Generated password: #{password}"
        password
      when "custom"
        password = prompt_for_secret("Custom password")
        raise Error, "Password cannot be blank." if blank?(password)

        password
      else
        raise Error, "Password strategy must be generated or custom."
      end
    end

    def confirm_share!(source:, slug:, access_mode:, replace_existing:, password:, interactive:, skip_confirmation:)
      return unless interactive
      return if skip_confirmation

      say ""
      say "Ready to upload:"
      say "  Path: #{source.display_path}"
      say "  Slug: #{slug}"
      say "  Access: #{access_mode}"
      say "  Replace existing: #{replace_existing ? 'yes' : 'no'}"
      say "  Password: #{password}" if password
      say ""

      raise Error, "Upload canceled." unless confirm("Continue with upload?", default: true)
    end

    def prompt_next_action(client:, response:)
      share_url = response.fetch("share_url")

      if response["access_mode"] == "protected"
        choice = prompt_for_value("Next action (share-url/expiring-link/done)", default: "done").downcase

        case choice
        when "share-url"
          copy_or_print("Share URL", share_url)
        when "expiring-link"
          preset = prompt_for_value("Expiring link preset (1_day/1_week/1_month)", default: "1_week")
          raise Error, "Unknown expiring link preset." unless LINK_PRESETS.key?(preset)

          link = client.create_link(slug: response.fetch("slug"), expires_in: preset)
          copy_or_print("Expiring link", link.fetch("url"))
        end
      else
        return unless confirm("Copy the share URL now?", default: false)

        copy_or_print("Share URL", share_url)
      end
    end

    def copy_or_print(label, value)
      if Clipboard.copy(value)
        say "#{label} copied to the clipboard."
      else
        say "#{label}: #{value}"
      end
    end

    def prompt_for_value(label, default: nil)
      raise Error, "#{label} is required." unless stdin.tty?

      prompt = default ? "#{label} [#{default}]: " : "#{label}: "
      stdout.print(prompt)
      stdout.flush

      answer = stdin.gets.to_s.strip
      answer.empty? ? default.to_s : answer
    end

    def prompt_for_secret(label)
      raise Error, "#{label} is required." unless stdin.tty?

      stdout.print("#{label}: ")
      stdout.flush
      secret = stdin.noecho(&:gets).to_s.strip
      stdout.puts
      secret
    end

    def confirm(prompt, default:)
      answer = prompt_for_value("#{prompt} [#{default ? 'Y/n' : 'y/N'}]")
      normalized = answer.to_s.strip.downcase
      return default if normalized.empty?

      %w[y yes].include?(normalized)
    end

    def interactive?(options)
      !options[:json] && stdin.tty? && stdout.tty?
    end

    def default_slug_for(path)
      input_path = File.expand_path(path)
      basename =
        if File.directory?(input_path)
          File.basename(input_path)
        else
          file_slug_stem(File.basename(input_path))
        end

      slugify(basename)
    end

    def file_slug_stem(filename)
      filename.sub(/(\.tar\.gz|\.tgz)\z/i, "").sub(/\.[^.]+\z/, "")
    end

    def slugify(value)
      value
        .to_s
        .downcase
        .gsub(/[^a-z0-9]+/, "-")
        .gsub(/\A-+|-+\z/, "")
        .gsub(/-{2,}/, "-")
    end

    def next_slug_candidate(slug)
      if slug =~ /-(\d+)\z/
        slug.sub(/-(\d+)\z/) { "-#{$1.to_i + 1}" }
      else
        "#{slug}-2"
      end
    end

    def say(message)
      stdout.puts(message)
    end

    def emit_error(message)
      if @json_errors
        stdout.puts JSON.pretty_generate({ error: message })
      else
        stderr.puts("Error: #{message}")
      end
    end

    def blank?(value)
      value.to_s.strip.empty?
    end

    def print_share_summary(response)
      say ""
      say "Bundle ready."
      say "Share URL: #{response.fetch('share_url')}"
      say "Password: #{response['password']}" if response["password"]
      say "Expiring link: #{response['signed_url']}" if response["signed_url"]
    end

    def print_usage
      stdout.puts <<~USAGE
        Usage:
          knyle-share login
          knyle-share <path> [options]

        Examples:
          knyle-share login
          knyle-share ./site --public
          knyle-share "./Summer in the Sierra.md" --protected --generate-password
      USAGE
      0
    end
  end
end
