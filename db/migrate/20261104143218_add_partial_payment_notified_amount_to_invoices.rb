class AddPartialPaymentNotifiedAmountToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :partial_payment_notified_amount, :integer, default: 0, null: false
  end
end
