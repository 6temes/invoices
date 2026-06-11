class RestructureAddresses < ActiveRecord::Migration[8.1]
  def up
    change_table :addresses do |t|
      t.string :country_code, limit: 2
      t.string :administrative_area
      t.string :locality
      t.string :sublocality
      t.string :street
      t.string :extended
    end

    # Migrate existing data: both addresses are Japanese
    execute <<~SQL
      UPDATE addresses SET country_code = 'JP', locality = line1, street = line2
    SQL

    change_column_null :addresses, :country_code, false

    change_table :addresses do |t|
      t.remove :line1, :line2, :country
    end

    remove_index :addresses, [ :addressable_type, :addressable_id ]
    add_index :addresses, [ :addressable_type, :addressable_id ], unique: true
  end

  def down
    remove_index :addresses, [ :addressable_type, :addressable_id ]

    change_table :addresses do |t|
      t.remove :country_code, :administrative_area, :locality, :sublocality, :street, :extended

      t.string :line1, null: false, default: ""
      t.string :line2
      t.string :country, null: false, default: ""
    end

    add_index :addresses, [ :addressable_type, :addressable_id ]
  end
end
