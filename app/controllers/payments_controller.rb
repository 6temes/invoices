class PaymentsController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  # Runs before set_invoice, so @invoice is unavailable — alert uses default locale
  rate_limit to: 5, within: 1.minute, only: :create, by: -> { request.remote_ip },
    with: -> { redirect_to public_payment_path(params[:token]), alert: t("invoice.payment_error") }

  before_action :set_invoice

  def show
    render :thank_you if @invoice.paid?
  end

  def create
    return redirect_to public_payment_path(params[:token]) unless @invoice.sent?

    session = find_or_create_checkout_session
    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.error.report e, context: { invoice_id: @invoice.id }
    redirect_to public_payment_path(params[:token]),
      alert: I18n.with_locale(@invoice.locale) { I18n.t("invoice.payment_error") }
  end

  private

  def set_invoice
    @invoice = Invoice.find_signed!(params[:token], purpose: :payment)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    render plain: "Invalid or expired payment link.", status: :not_found
  end

  def find_or_create_checkout_session
    @invoice.reload

    if @invoice.stripe_checkout_session_id.present?
      existing = Stripe::Checkout::Session.retrieve @invoice.stripe_checkout_session_id
      return existing if existing.status == "open"
    end

    @invoice.create_checkout_session!
  end
end
