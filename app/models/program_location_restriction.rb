class ProgramLocationRestriction < ActiveRecord::Base
  self.table_name = "program_location_restriction"
  self.primary_key = "program_location_restriction_id"
  include Openmrs
  belongs_to :program,->{where(retired: 0)}, optional: true
  belongs_to :location, ->{where(retired: 0)}, optional: true
  
  def filter_programs(programs)
    programs.reject {|program| self.program_id == program.program_id}
  end
  
  def filter_patient_identifiers(identifiers)
    type_map = ProgramPatientIdentifierTypeMap.where(program_id: self.program_id)
    type_map = type_map.map{|t| t.patient_identifier_type_id}
    identifiers.reject {|ident| type_map.include?(ident.identifier_type)}
  end
  
  def filter_relationships(relationships)
    type_map = ProgramRelationshipTypeMap.where(program_id: self.program_id)
    type_map = type_map.map{|t| t.relationship_type_id}
    relationships.reject {|rel| type_map.include?(rel.relationship)}
  end
  
  def filter_orders(orders)
    type_map = ProgramOrdersMap.where(program_id: self.program_id)
    type_map = type_map.map{|t| t.concept_id}
    orders.reject {|order| type_map.include?(order.concept_id)}
  end
  
  def filter_encounters(encounters)
    type_map = ProgramEncounterTypeMap.where(program_id: self.program_id)
    type_map = type_map.map{|t| t.encounter_type_id}
    encounters.reject {|enc| type_map.include?(enc.encounter_type)}
  end
end
