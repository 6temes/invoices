class AddOriginToInvoiceLineItems < ActiveRecord::Migration[8.1]
  def change
    add_column :invoice_line_items, :origin, :string, default: "manual", null: false
  end
end
