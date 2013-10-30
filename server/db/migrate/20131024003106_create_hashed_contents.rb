class CreateHashedContents < ActiveRecord::Migration
  def change
    create_table :hashed_contents do |t|
      t.string :type
      t.string :sha2, :limit => 64, :null => false
      t.text :content
      t.references :content_owner, :polymorphic => true

      t.timestamps
    end
    add_index :hashed_contents, [:content_owner_type, :content_owner_id]
    add_index :hashed_contents, :sha2, :unique => true
  end
end
