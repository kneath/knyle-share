module KnyleShare
  module Clipboard
    COMMANDS = {
      "pbcopy" => [ "pbcopy" ],
      "wl-copy" => [ "wl-copy" ],
      "xclip" => [ "xclip", "-selection", "clipboard" ],
      "xsel" => [ "xsel", "--clipboard", "--input" ]
    }.freeze

    module_function

    def available?
      !command_name.nil?
    end

    def copy(text)
      command = command_spec
      return false unless command

      IO.popen(command, "w") { |io| io.write(text) }
      true
    rescue SystemCallError
      false
    end

    def command_spec
      name = command_name
      name ? COMMANDS.fetch(name) : nil
    end
    private_class_method :command_spec

    def command_name
      @command_name ||= COMMANDS.keys.find { |name| system("command -v #{name} >/dev/null 2>&1") }
    end
    private_class_method :command_name
  end
end
