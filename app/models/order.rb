class Order < ActiveRecord::Base
  before_save :before_save
  before_create :before_create

  self.table_name = "orders"
  self.primary_key = "order_id"
  include Openmrs
  belongs_to :order_type, -> { where retired: 0 }
  belongs_to :concept, -> { where retired: 0 }
  belongs_to :encounter, -> { where voided: 0 }
  belongs_to :patient, -> { where voided: 0 }
  belongs_to :provider, -> { where voided: 0 }, foreign_key: :orderer, class_name: :User
  belongs_to :observation, -> { where voided: 0 }, foreign_key: :obs_id, class_name: :Observation
  has_one :drug_order # no default scope
  
  scope :current,-> { includes(:encounter).where('DATE(encounter.encounter_datetime) = CURRENT_DATE()') }
  scope :historical, -> { includes(:encounter).where('DATE(encounter.encounter_datetime) <> CURRENT_DATE()') }
  scope :unfinished, -> {where("discontinued = 0 AND auto_expire_date > NOW()")}
  scope :finished, -> {where("discontinued = 1 OR auto_expire_date < NOW()")}
  scope :arv, lambda {|order|
    arv_concept = ConceptName.find_by_name("ANTIRETROVIRAL DRUGS").concept_id
    arv_drug_concepts = ConceptSet.where(['concept_set = ?', arv_concept])
    where(['concept_id IN (?)', arv_drug_concepts.map(&:concept_id)])
  }
  scope :labs, -> {includes(:drug_order).where('drug_order.drug_inventory_id is NULL')}
  scope :prescriptions, -> {includes(:drug_order).where("drug_order.drug_inventory_id is NOT NULL")}
  
  after_save do |o|
    drug_order = DrugOrder.where(["order_id =?", o.order_id]).last
    Pharmacy.update_stock_record(drug_order.drug_inventory_id, Date.today) unless drug_order.blank?
  end

  def after_void(reason = nil)
    # TODO Should we be voiding the associated meta obs that point back to this?
  end

  def to_s
    "#{drug_order}"
  end
  
end
