class ChangeBankCodesToNotNull < ActiveRecord::Migration[8.1]
  def change
    change_column_null :businesses, :bank_code, false
    change_column_null :businesses, :bank_branch_code, false
  end
end
