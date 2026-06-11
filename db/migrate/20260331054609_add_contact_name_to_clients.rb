class AddContactNameToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :contact_name, :string
  end
end
