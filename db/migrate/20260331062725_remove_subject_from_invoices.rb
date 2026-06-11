class RemoveSubjectFromInvoices < ActiveRecord::Migration[8.1]
  def change
    remove_column :invoices, :subject, :string
  end
end
