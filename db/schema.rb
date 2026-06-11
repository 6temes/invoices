# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_26_134208) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
    t.index ["blob_id"], name: "index_active_storage_variant_records_on_blob_id"
  end

  create_table "addresses", force: :cascade do |t|
    t.integer "addressable_id", null: false
    t.string "addressable_type", null: false
    t.string "administrative_area"
    t.string "country_code", limit: 2, null: false
    t.datetime "created_at", null: false
    t.string "extended"
    t.string "locality"
    t.string "postal_code", null: false
    t.string "street"
    t.string "sublocality"
    t.datetime "updated_at", null: false
    t.index ["addressable_type", "addressable_id"], name: "index_addresses_on_addressable_type_and_addressable_id", unique: true
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "businesses", force: :cascade do |t|
    t.string "bank_account_holder", null: false
    t.string "bank_account_number", null: false
    t.string "bank_account_type", null: false
    t.string "bank_branch", null: false
    t.string "bank_branch_code", null: false
    t.string "bank_code", null: false
    t.string "bank_name", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.integer "next_invoice_number", null: false
    t.decimal "tax_rate", precision: 5, scale: 2, null: false
    t.string "tax_registration_number", null: false
    t.datetime "updated_at", null: false
  end

  create_table "clients", force: :cascade do |t|
    t.string "contact_name"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.text "github_repos"
    t.string "locale", default: "en", null: false
    t.string "name", null: false
    t.string "payment_method", default: "bank_transfer", null: false
    t.integer "payment_terms_days", null: false
    t.string "stripe_customer_id"
    t.string "tax_registration_number"
    t.datetime "updated_at", null: false
  end

  create_table "extra_hours", force: :cascade do |t|
    t.integer "client_id", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "github_url"
    t.decimal "hours", precision: 6, scale: 2, null: false
    t.integer "invoice_line_item_id"
    t.date "performed_on", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_extra_hours_on_client_id"
    t.index ["invoice_line_item_id"], name: "index_extra_hours_on_invoice_line_item_id"
  end

  create_table "informant_error_groups", force: :cascade do |t|
    t.string "controller_action"
    t.datetime "created_at", null: false
    t.integer "duplicate_of_id"
    t.string "error_class", null: false
    t.string "fingerprint", null: false
    t.string "first_backtrace_line"
    t.datetime "first_seen_at", null: false
    t.datetime "fix_deployed_at"
    t.string "fix_pr_url"
    t.string "fix_sha"
    t.string "job_class"
    t.datetime "last_notified_at"
    t.datetime "last_occurrence_stored_at"
    t.datetime "last_seen_at", null: false
    t.text "message"
    t.text "notes"
    t.string "original_sha"
    t.datetime "resolved_at"
    t.string "severity", default: "error"
    t.string "status", default: "unresolved", null: false
    t.integer "total_occurrences", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["duplicate_of_id"], name: "index_informant_error_groups_on_duplicate_of_id"
    t.index ["error_class"], name: "index_informant_error_groups_on_error_class"
    t.index ["fingerprint"], name: "index_informant_error_groups_on_fingerprint", unique: true
    t.index ["status", "last_seen_at"], name: "index_informant_error_groups_on_status_and_last_seen_at"
    t.index ["status", "original_sha"], name: "index_informant_error_groups_on_status_and_original_sha"
    t.index ["status", "resolved_at"], name: "index_informant_error_groups_on_status_and_resolved_at"
    t.index ["status", "total_occurrences"], name: "index_informant_error_groups_on_status_and_total_occurrences"
    t.index ["status", "updated_at"], name: "index_informant_error_groups_on_status_and_updated_at"
    t.check_constraint "duplicate_of_id IS NULL OR duplicate_of_id != id", name: "check_no_self_duplicate"
  end

  create_table "informant_occurrences", force: :cascade do |t|
    t.json "backtrace"
    t.json "breadcrumbs"
    t.datetime "created_at", null: false
    t.json "custom_context"
    t.json "environment_context"
    t.integer "error_group_id", null: false
    t.json "exception_chain"
    t.string "git_sha"
    t.json "request_context"
    t.datetime "updated_at", null: false
    t.json "user_context"
    t.index ["created_at"], name: "index_informant_occurrences_on_created_at"
    t.index ["error_group_id", "created_at"], name: "index_informant_occurrences_on_error_group_id_and_created_at"
    t.index ["error_group_id"], name: "index_informant_occurrences_on_error_group_id"
  end

  create_table "invoice_line_items", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.integer "invoice_id", null: false
    t.string "item_type", null: false
    t.string "origin", default: "manual", null: false
    t.decimal "quantity", precision: 8, scale: 2, null: false
    t.integer "unit_price", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_invoice_line_items_on_invoice_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.date "billing_month"
    t.integer "client_id", null: false
    t.datetime "created_at", null: false
    t.date "due_date", null: false
    t.integer "invoice_number", null: false
    t.date "issue_date", null: false
    t.string "locale", null: false
    t.text "notes"
    t.integer "paid_amount", default: 0, null: false
    t.date "paid_on"
    t.datetime "sent_at"
    t.string "status", default: "draft", null: false
    t.string "stripe_checkout_session_id"
    t.string "stripe_payment_intent_id"
    t.integer "subtotal", default: 0, null: false
    t.integer "tax_amount", default: 0, null: false
    t.decimal "tax_rate", precision: 5, scale: 2, null: false
    t.integer "total", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["billing_month"], name: "index_invoices_on_billing_month"
    t.index ["client_id", "billing_month"], name: "index_invoices_on_client_id_and_billing_month", unique: true
    t.index ["client_id"], name: "index_invoices_on_client_id"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number", unique: true
    t.index ["issue_date", "invoice_number"], name: "index_invoices_on_issue_date_and_invoice_number"
  end

  create_table "retainers", force: :cascade do |t|
    t.integer "client_id", null: false
    t.datetime "created_at", null: false
    t.date "ends_on"
    t.integer "hourly_rate", null: false
    t.boolean "includes_infrastructure", default: false, null: false
    t.integer "monthly_amount", null: false
    t.decimal "monthly_hours", precision: 6, scale: 2, null: false
    t.date "starts_on", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_retainers_on_client_id"
    t.index ["client_id"], name: "index_retainers_one_active_per_client", unique: true, where: "ends_on IS NULL"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.string "whodunnit"
    t.index ["created_at"], name: "index_versions_on_created_at"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "extra_hours", "clients"
  add_foreign_key "extra_hours", "invoice_line_items"
  add_foreign_key "informant_error_groups", "informant_error_groups", column: "duplicate_of_id"
  add_foreign_key "informant_occurrences", "informant_error_groups", column: "error_group_id"
  add_foreign_key "invoice_line_items", "invoices"
  add_foreign_key "invoices", "clients"
  add_foreign_key "retainers", "clients"
  add_foreign_key "sessions", "users"
end
