class CreatePredicts < ActiveRecord::Migration
  def change
    create_table :predicts do |t|
      t.string :name, :null => false
      t.references :client
      t.string :file, :null => false
      t.string :result

      t.timestamps
    end
    add_index :predicts, :client_id
    add_index :predicts, [:name, :file, :client_id], :unique => true
  end
end
