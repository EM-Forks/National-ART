class SerializedObject < ActiveRecord::Base
	self.table_name = "serialized_object"
	self.primary_key = "serialized_object_id"
	include Openmrs

end
