class AddTaxRegistrationNumberToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :tax_registration_number, :string
  end
end
