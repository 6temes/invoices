class InvoiceGenerationJob < ApplicationJob
  queue_as :default

  def perform
    business = Business.instance
    billing_month = Date.current.prev_month.beginning_of_month
    already_billed = Invoice.where(billing_month: billing_month).pluck(:client_id).to_set

    Client.includes(:retainers).find_each do |client|
      retainer = client.active_retainer
      next unless retainer
      next if already_billed.include?(client.id)

      invoice = client.invoices.build(
        locale: client.locale,
        billing_month:,
        issue_date: Date.current,
        due_date: Date.current + client.payment_terms_days.days,
        tax_rate: business.tax_rate
      )

      invoice.build_from_retainer
      invoice.save!
      invoice.prepare_for_delivery!
      InvoiceDeliveryJob.perform_later invoice
    rescue ActiveRecord::RecordInvalid => e
      Rails.error.report e, context: { client_id: client.id }
    end
  end
end
