class AddBankCodesToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :bank_code, :string
    add_column :businesses, :bank_branch_code, :string

    reversible do |dir|
      dir.up do
        execute "UPDATE businesses SET bank_code = '0005', bank_branch_code = '152'"
      end
    end
  end
end
