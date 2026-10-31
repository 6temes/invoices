class Webhooks::StripeEventNotificationsController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection

  def create
    StripeEventNotification.receive request.raw_post, request.headers["Stripe-Signature"]
    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  end
end
