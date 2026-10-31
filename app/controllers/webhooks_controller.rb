class WebhooksController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection

  def stripe
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

    event = Stripe::Webhook.construct_event(
      payload, sig_header, Rails.application.credentials.dig(:stripe, :webhook_secret)
    )

    case event.type
    when "checkout.session.completed", "checkout.session.expired"
      Invoice.apply_checkout_session event.data.object
    end

    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  end
end
