class BartOneEncounter < ActiveRecord::Base
 self.table_name = "encounter"
  has_many :bart_one_observations, foreign_key: :encounter_id, optional: true, dependent: :destroy do
    def find_by_concept_id(concept_id)
      where(["voided = 0 and concept_id = ?", concept_id])
    end
    def find_by_concept_name(concept_name)
      where(["voided = 0 and concept_id = ?", Concept.find_by_name(concept_name).id])
    end
    def find_first_by_concept_name(concept_name)
      where(["voided = 0 and concept_id = ?", Concept.find_by_name(concept_name).id]).order("obs_datetime")
    end
    def find_last_by_concept_name(concept_name)
      where(["voided = 0 and concept_id = ?", Concept.find_by_name(concept_name).id]).order("obs_datetime DESC")
    end
  end
  has_many :orders, foreign_key: :encounter_id, dependent: :destroy
  has_many :bart_one_drug_orders, through: :bart_one_orders,foreign_key: 'order_id'
  has_many :notes, foreign_key: :encounter_id, dependent: :destroy
  has_many :concept_proposals, foreign_key: :encounter_id, dependent: :destroy
  belongs_to :patient, foreign_key: :patient_id
  belongs_to :type, class_name: "EncounterType", foreign_key: :encounter_type
  belongs_to :provider, class_name: "User", foreign_key: :provider_id
  belongs_to :created_by, class_name: "User", foreign_key: :creator
  belongs_to :form
  belongs_to :location

  self.primary_key =  "encounter_id"
def voided?

    # check void status for encounter's orders if its a Dispensation
    self.bart_one_drug_orders.each{|drug_order|
      return false unless drug_order.order.voided?
    } if self.name == "Give drugs"

    # check void status of this encounter's observations
    self.bart_one_observations.each{|observation|
      return false unless observation.voided?
    } unless self.name == "Give drugs"

    return true
  end
  
  def name
    return self.type.name unless self.type.nil?
  end

end