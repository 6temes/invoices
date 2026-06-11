class RemoveSubjectFromRetainers < ActiveRecord::Migration[8.1]
  def change
    remove_column :retainers, :subject, :string, null: false
  end
end
