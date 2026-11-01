class RenameClientPaymentMethodCreditCardToStripe < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE clients SET payment_method = 'stripe' WHERE payment_method = 'credit_card'"
  end

  def down
    execute "UPDATE clients SET payment_method = 'credit_card' WHERE payment_method = 'stripe'"
  end
end
