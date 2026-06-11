# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.connect_src :self, "https://cloudflareinsights.com"
    policy.font_src    :self, :data
    policy.img_src     :self, :data
    policy.object_src  :none
    policy.script_src  :self, "https://static.cloudflareinsights.com"
    # Turbo injects inline styles for cache placeholders and morphing.
    # unsafe_inline for style-src is low risk (no script execution) and
    # avoids breaking Turbo Drive's rendering pipeline.
    policy.style_src   :self, :unsafe_inline
  end

  # Generate nonces for permitted importmap and inline scripts.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
