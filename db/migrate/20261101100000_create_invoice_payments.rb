class CreateInvoicePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :invoice_payments do |t|
      t.references :invoice, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false, default: "succeeded"
      t.integer :amount, null: false
      t.integer :excess_amount, null: false, default: 0
      t.string :stripe_payment_intent_id
      t.string :stripe_refund_id
      t.string :idempotency_key
      t.timestamps

      t.index :stripe_payment_intent_id, unique: true
      t.index :idempotency_key, unique: true
      t.check_constraint "amount >= 0 AND excess_amount >= 0", name: "invoice_payments_amounts_not_negative"
    end
  end
end
