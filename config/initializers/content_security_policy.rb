# Be sure to restart your server when you modify this file.

# A content security policy for the pages the app renders itself: admin,
# markdown, file listings, media, and password pages. Uploaded static sites
# opt out (see Public::BaseController#render_html_asset), since their own
# scripts and styles are the point.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

admin_host = ENV.fetch("ADMIN_HOST", "admin.lvh.me")
public_host = ENV.fetch("PUBLIC_HOST", "share.lvh.me")

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    # Views use inline style attributes; scripts are what the policy guards.
    policy.style_src :self, :unsafe_inline
    # Bundle images, media, PDFs, and admin uploads all go to presigned S3 URLs.
    policy.img_src :self, :https, :data, :blob
    policy.media_src :self, :https, :blob
    policy.frame_src :self, :https
    policy.connect_src :self, :https
    policy.font_src :self, :https, :data
    policy.object_src :none
    policy.base_uri :self
    # Form posts redirect to GitHub for sign-in, and legacy /:slug/access
    # posts redirect to the bundle's own subdomain.
    policy.form_action :self, "#{admin_host}:*", "#{public_host}:*", "*.#{public_host}:*", "https://github.com"
    policy.frame_ancestors :self
  end

  # A fresh nonce per response. Rails leaves the CSP header off 304s, so a
  # cached page keeps the policy that matches its nonce.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
