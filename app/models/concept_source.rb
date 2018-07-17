class ConceptSource < ActiveRecord::Base
  self.table_name = "concept_source"
  self.primary_key  = "concept_source_id"
  
  has_many :concept_maps, class_name: :ConceptMap, foreign_key: :source # no default scope
  has_many :concepts, through: :concept_maps
end

