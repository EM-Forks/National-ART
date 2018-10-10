class StockManagement < ActiveRecord::Base
  self.table_name = "pharmacy_obs"
  self.primary_key = "pharmacy_module_id"
  include Openmrs
  #before_create :update_stock_record

  scope :active, ->{where(voided: 0)}


  def self.closing_stock(drug_id, date)
    encounter_type = PharmacyEncounterType.find_by_name("Tins currently in stock")

    stock = self.where(drug_id: drug_id, encounter_date: date,
      pharmacy_encounter_type: encounter_type.id)

    stock.last.value_numeric rescue 0
  end

  def self.latest_drug_stock(drug_id)
    encounter_type = PharmacyEncounterType.find_by_name("Tins currently in stock")

    max_date = self.where(drug_id: drug_id, 
      pharmacy_encounter_type: encounter_type.id).select("MAX(encounter_date) AS encounter_date")

    max_date = max_date.first.encounter_date rescue nil

    value_numeric = self.where(drug_id: drug_id, 
      pharmacy_encounter_type: encounter_type.id,
      encounter_date: max_date).last.value_numeric rescue 0

    encounter_type = PharmacyEncounterType.find_by_name("New deliveries")
   
    max_date = self.where(drug_id: drug_id, 
      pharmacy_encounter_type: encounter_type.id).select("MAX(encounter_date) AS encounter_date")

    max_date = max_date.first.encounter_date rescue nil
    expiry_date = self.where(drug_id: drug_id, 
      pharmacy_encounter_type: encounter_type.id,
      encounter_date: max_date).last.expiry_date rescue nil

    return {stock: value_numeric, expiry_date: expiry_date}  

  end


end
