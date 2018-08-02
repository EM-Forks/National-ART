class DDECountry < ActiveRecord::Base
	self.table_name = "dde_country"
	self.primary_key = "country_id"

	belongs_to :region, optional: true

end
