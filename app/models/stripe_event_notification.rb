class StripeEventNotification
  UnhandledEventError = Class.new(StandardError)

  def self.receive(payload, signature)
    handler.handle payload, signature
  end

  # Built per request: the gem refuses new callbacks once a handler has handled an
  # event, and there is no state worth sharing between requests.
  def self.handler
    client = Stripe::StripeClient.new(Stripe.api_key)
    secret = Rails.configuration.x.stripe.thin_webhook_secret

    Stripe::StripeEventNotificationHandler.new(client, secret) do |notification|
      Rails.error.report UnhandledEventError.new("Unhandled Stripe event notification"),
        context: { event_id: notification.id, type: notification.type }, handled: true
    end.tap do |handler|
      handler.on_v1_checkout_session_completed { CheckoutSessionReconciliationJob.perform_later it.related_object.id }
      handler.on_v1_checkout_session_expired { CheckoutSessionReconciliationJob.perform_later it.related_object.id }
      handler.on_v2_core_event_destination_ping { }
    end
  end
  private_class_method :handler
end
