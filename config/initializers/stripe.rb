Stripe.api_key = Rails.application.credentials.dig(:stripe, :secret_key) || "sk_test_placeholder"
# Pinned so a stripe gem upgrade cannot change API behaviour; move it on purpose after reading Stripe's changelog.
Stripe.api_version = "2026-08-26.dahlia"
