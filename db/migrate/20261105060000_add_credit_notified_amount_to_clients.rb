class AddCreditNotifiedAmountToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :credit_notified_amount, :integer, default: 0, null: false
    add_column :clients, :prepaid_return_fee_payment_intent_id, :string
  end
end
