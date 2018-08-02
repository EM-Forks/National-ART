class DDEDistrict < ActiveRecord::Base
	self.table_name = "dde_district"
	self.primary_key = "district_id"

	belongs_to :region, optional: true

end
