require_relative "../../lib/knyle_share/password_generator"

class GeneratedPassword
  def self.generate
    KnyleShare::PasswordGenerator.generate
  end
end
