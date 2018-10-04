class DrugSet < ActiveRecord::Base
  self.table_name = "drug_set"
	self.primary_key = "drug_set_id"
  include Openmrs


end
