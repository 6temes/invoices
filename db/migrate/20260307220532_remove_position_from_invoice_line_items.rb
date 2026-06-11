class RemovePositionFromInvoiceLineItems < ActiveRecord::Migration[8.1]
  def change
    remove_column :invoice_line_items, :position, :integer, default: 0, null: false
  end
end
