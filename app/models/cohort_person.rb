class CohortPerson < ActiveRecord::Base
  self.table_name = "person"
  self.primary_key = "person_id"

  has_many :names,->{where(voided: 0)}, class_name: 'CohortPersonName', foreign_key: :person_id,
    dependent: :destroy, order: 'person_name.preferred DESC'
end