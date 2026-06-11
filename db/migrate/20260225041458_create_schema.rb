class CreateSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.timestamps
    end

    add_index :users, :email_address, unique: true

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    create_table :addresses do |t|
      t.references :addressable, polymorphic: true, null: false
      t.string :postal_code, null: false
      t.string :line1, null: false
      t.string :line2
      t.string :country, null: false
      t.timestamps
    end

    create_table :businesses do |t|
      t.string :name, null: false
      t.string :tax_registration_number, null: false
      t.string :bank_name, null: false
      t.string :bank_branch, null: false
      t.string :bank_account_holder, null: false
      t.string :bank_account_type, null: false
      t.string :bank_account_number, null: false
      t.string :email, null: false
      t.decimal :tax_rate, precision: 5, scale: 2, null: false
      t.integer :next_invoice_number, null: false
      t.timestamps
    end

    create_table :clients do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.integer :locale, null: false
      t.integer :payment_method, null: false
      t.integer :payment_terms_days, null: false
      t.string :stripe_customer_id
      t.text :github_repos
      t.timestamps
    end

    create_table :retainers do |t|
      t.references :client, null: false, foreign_key: true
      t.string :subject, null: false
      t.string :description, null: false
      t.decimal :monthly_hours, precision: 6, scale: 2, null: false
      t.integer :monthly_amount, null: false
      t.integer :hourly_rate, null: false
      t.boolean :includes_infrastructure, default: false, null: false
      t.date :starts_on, null: false
      t.date :ends_on
      t.timestamps
    end

    add_index :retainers, :client_id, unique: true, where: "ends_on IS NULL", name: "index_retainers_one_active_per_client"

    create_table :invoices do |t|
      t.references :client, null: false, foreign_key: true
      t.integer :invoice_number, null: false
      t.string :locale, null: false
      t.string :subject
      t.date :billing_month
      t.date :issue_date, null: false
      t.date :due_date, null: false
      t.integer :status, default: 0, null: false
      t.integer :subtotal, default: 0, null: false
      t.decimal :tax_rate, precision: 5, scale: 2, null: false
      t.integer :tax_amount, default: 0, null: false
      t.integer :total, default: 0, null: false
      t.integer :paid_amount, default: 0, null: false
      t.date :paid_on
      t.text :notes
      t.string :stripe_checkout_session_id
      t.string :stripe_payment_intent_id
      t.datetime :sent_at
      t.timestamps
    end

    add_index :invoices, :invoice_number, unique: true
    add_index :invoices, [ :client_id, :billing_month ], unique: true
    add_index :invoices, :status
    add_index :invoices, [ :issue_date, :invoice_number ]
    add_index :invoices, :billing_month

    create_table :invoice_line_items do |t|
      t.references :invoice, null: false, foreign_key: true
      t.string :item_type, null: false
      t.string :description, null: false
      t.decimal :quantity, precision: 8, scale: 2, null: false
      t.integer :unit_price, null: false
      t.integer :amount, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end

    create_table :extra_hours do |t|
      t.references :client, null: false, foreign_key: true
      t.references :invoice_line_item, null: true, foreign_key: true
      t.string :description
      t.decimal :hours, precision: 6, scale: 2, null: false
      t.date :performed_on, null: false
      t.string :github_url
      t.timestamps
    end

    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :name, null: false
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :api_tokens, :token_digest, unique: true

    create_table :active_storage_blobs do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum

      t.datetime :created_at, null: false

      t.index [ :key ], unique: true
    end

    create_table :active_storage_attachments do |t|
      t.string :name, null: false
      t.references :record, null: false, polymorphic: true, index: false
      t.references :blob, null: false

      t.datetime :created_at, null: false

      t.index [ :record_type, :record_id, :name, :blob_id ], name: :index_active_storage_attachments_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end

    create_table :active_storage_variant_records do |t|
      t.belongs_to :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.string :variation_digest, null: false

      t.index [ :blob_id, :variation_digest ], name: :index_active_storage_variant_records_uniqueness, unique: true
    end
  end
end
