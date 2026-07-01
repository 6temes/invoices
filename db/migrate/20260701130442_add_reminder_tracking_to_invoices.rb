class AddReminderTrackingToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :reminded_at, :datetime
    add_column :invoices, :reminders_count, :integer, null: false, default: 0
  end
end
