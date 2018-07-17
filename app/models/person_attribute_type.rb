class PersonAttributeType < ActiveRecord::Base
  self.table_name = "person_attribute_type"
  self.primary_key = "person_attribute_type_id"
  include Openmrs
  has_many :person_attributes, ->{where(voided:0)}
end