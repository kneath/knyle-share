# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Signed bundle access links carry their token in ?access=. Match exactly so
  # access_mode still shows up in logs.
  /\Aaccess\z/
]

# Redirects to a bundle's canonical host keep ?access= in the location, which
# Rails logs and Sentry records as a breadcrumb.
Rails.application.config.filter_redirect << /[?&]access=/
