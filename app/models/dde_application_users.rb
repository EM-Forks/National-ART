class DdeApplicationUsers < ActiveRecord::Base
	self.table_name = "dde_application_users"
	self.primary_key = "application_id"
end
