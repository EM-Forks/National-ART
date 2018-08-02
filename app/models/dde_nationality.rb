class DDENationality < ActiveRecord::Base
	self.table_name = "dde_nationality"
	self.primary_key = "nationality_id"

	belongs_to :region, optional: true

end
