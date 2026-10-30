class AddPurposeToApiTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :api_tokens, :purpose, :string, default: "chrome_extension", null: false
  end
end
