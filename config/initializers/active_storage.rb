Rails.application.config.active_storage.urls_expire_in = 5.minutes

# The app only serves the files it generates to the signed-in owner, so Active Storage's
# public controllers (direct uploads, blob redirects, disk service) require a session too.
Rails.application.config.to_prepare do
  ActiveStorage::BaseController.include Authentication
end
