class CreateLocationTags < ActiveRecord::Migration[5.2]
=begin
  def self.up
    create_table :location_tags, :id => false do |t|
      t.integer :location_tag_id, :null => false

      t.timestamps
    end
    add_index(:location_tags, :location_tag_id, :unique => true)
  end

  def self.down
    drop_table :location_tags
  end
=end
end
