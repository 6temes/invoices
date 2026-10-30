class RenameReadInvoicesPurposeToAgent < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE api_tokens SET purpose = 'agent' WHERE purpose = 'read_invoices'"
  end

  def down
    execute "UPDATE api_tokens SET purpose = 'read_invoices' WHERE purpose = 'agent'"
  end
end
