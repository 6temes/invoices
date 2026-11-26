# The app uses none of these browser features. Rails sends the list as the legacy
# Feature-Policy header; Permissions-Policy carries the same list for current browsers.
denied_features = %i[
  accelerometer ambient_light_sensor autoplay camera display_capture encrypted_media
  fullscreen geolocation gyroscope hid idle_detection keyboard_map magnetometer
  microphone midi payment picture_in_picture screen_wake_lock serial sync_xhr usb web_share
].freeze

Rails.application.config.permissions_policy do |policy|
  denied_features.each { policy.public_send(it, :none) }
end

Rails.application.config.action_dispatch.default_headers["Permissions-Policy"] =
  denied_features.map { "#{it.to_s.dasherize}=()" }.join(", ")
