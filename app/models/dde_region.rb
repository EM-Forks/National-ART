class DDERegion < ActiveRecord::Base
  self.table_name = "dde_region"
  self.primary_key = "region_id"
  
  has_many :districts, foreign_key: :region_id, optional: true
end
