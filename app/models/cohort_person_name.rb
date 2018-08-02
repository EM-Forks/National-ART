class CohortPersonName < ActiveRecord::Base
  self.table_name = "person_name"
  self.primary_key = "person_name_id"

  belongs_to :person,-> {where(voided:0)}, class_name: 'CohortPerson', foreign_key: :person_id, optional: true
  
end