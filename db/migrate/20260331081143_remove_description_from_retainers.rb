class RemoveDescriptionFromRetainers < ActiveRecord::Migration[8.1]
  def change
    remove_column :retainers, :description, :string, null: false
  end
end
