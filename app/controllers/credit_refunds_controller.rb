class CreditRefundsController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  # Runs before set_client, so the alert uses the default locale.
  rate_limit to: 5, within: 1.minute, only: :create, by: -> { request.remote_ip },
    with: -> { redirect_to credit_refund_path(params[:token]), alert: t("invoice.payment_error") }

  before_action :set_business
  before_action :set_client
  around_action :use_client_locale

  def show
    @balance = @client.cash_balance
  end

  def create
    shown_balance = params[:balance].to_i
    returned = @client.returnable_credit(shown_balance)

    case @client.refund_cash_balance!(shown_balance)
    when :returned
      @returned = returned
    when :nothing_to_return
      @balance = shown_balance
      render :show
    when :changed
      @balance = @client.cash_balance
      flash.now[:alert] = t("credit_refund.balance_changed")
      render :show, status: :unprocessable_entity
    end
  rescue Stripe::StripeError => e
    Rails.error.report e, context: { client_id: @client.id }
    redirect_to credit_refund_path(params[:token]), alert: t("invoice.payment_error")
  end

  private

  def set_business
    @business = Business.instance
  end

  def set_client
    @client = Client.find_by_token_for!(:credit_refund, params[:token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    render :invalid_link, status: :not_found
  end

  def use_client_locale(&)
    I18n.with_locale(@client.locale, &)
  end
end
