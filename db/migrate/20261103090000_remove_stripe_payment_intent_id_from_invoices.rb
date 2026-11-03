require_relative "20261101100100_backfill_invoice_payments"

class RemoveStripePaymentIntentIdFromInvoices < ActiveRecord::Migration[8.1]
  # An invoice paid by a container that predates the ledger has no payment row
  # yet, and this column is the last record of how it was paid.
  def up
    BackfillInvoicePayments.new.up
    remove_column :invoices, :stripe_payment_intent_id
  end

  def down
    add_column :invoices, :stripe_payment_intent_id, :string
  end
end
