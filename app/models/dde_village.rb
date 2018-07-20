class DDEVillage < ActiveRecord::Base
	self.table_name = "dde_village"
	self.primary_key = "village_id"

	belongs_to :traditional_authority

end
