class ConvertEnumsFromIntegersToStrings < ActiveRecord::Migration[8.1]
  def up
    # Invoice status: 0=draft, 1=sent, 2=paid
    rename_column :invoices, :status, :status_int
    add_column :invoices, :status, :string, default: "draft", null: false
    execute <<~SQL
      UPDATE invoices SET status = CASE status_int
        WHEN 0 THEN 'draft'
        WHEN 1 THEN 'sent'
        WHEN 2 THEN 'paid'
      END
    SQL
    remove_column :invoices, :status_int

    # Client locale: 0=en, 1=ja
    rename_column :clients, :locale, :locale_int
    add_column :clients, :locale, :string, default: "en", null: false
    execute <<~SQL
      UPDATE clients SET locale = CASE locale_int
        WHEN 0 THEN 'en'
        WHEN 1 THEN 'ja'
      END
    SQL
    remove_column :clients, :locale_int

    # Client payment_method: 0=bank_transfer, 1=credit_card
    rename_column :clients, :payment_method, :payment_method_int
    add_column :clients, :payment_method, :string, default: "bank_transfer", null: false
    execute <<~SQL
      UPDATE clients SET payment_method = CASE payment_method_int
        WHEN 0 THEN 'bank_transfer'
        WHEN 1 THEN 'credit_card'
      END
    SQL
    remove_column :clients, :payment_method_int
  end

  def down
    # Invoice status
    rename_column :invoices, :status, :status_str
    add_column :invoices, :status, :integer, default: 0, null: false
    execute <<~SQL
      UPDATE invoices SET status = CASE status_str
        WHEN 'draft' THEN 0
        WHEN 'sent' THEN 1
        WHEN 'paid' THEN 2
      END
    SQL
    remove_column :invoices, :status_str

    # Client locale
    rename_column :clients, :locale, :locale_str
    add_column :clients, :locale, :integer, default: 0, null: false
    execute <<~SQL
      UPDATE clients SET locale = CASE locale_str
        WHEN 'en' THEN 0
        WHEN 'ja' THEN 1
      END
    SQL
    remove_column :clients, :locale_str

    # Client payment_method
    rename_column :clients, :payment_method, :payment_method_str
    add_column :clients, :payment_method, :integer, default: 0, null: false
    execute <<~SQL
      UPDATE clients SET payment_method = CASE payment_method_str
        WHEN 'bank_transfer' THEN 0
        WHEN 'credit_card' THEN 1
      END
    SQL
    remove_column :clients, :payment_method_str
  end
end
