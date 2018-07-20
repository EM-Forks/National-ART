class RelationshipType < ActiveRecord::Base
  self.table_name = "relationship_type"
  self.primary_key = "relationship_type_id"
  include Openmrs
  default_scope {order('weight DESC')}
  has_many :relationships, ->{where(voided: 0)}
end