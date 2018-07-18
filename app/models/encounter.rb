require "will_paginate"
class Encounter < ActiveRecord::Base
  self.table_name = "encounter"
  self.primary_key = "encounter_id"

  #include Openmrs

  has_many :observations, -> { where voided: 0 }, dependent: :destroy
  has_many :drug_orders, foreign_key: "order_id", through: "orders"
  has_many :orders, -> { where voided: 0 }, dependent: :destroy
  belongs_to :type, -> { where retired: 0 }, class_name: "EncounterType", foreign_key: "encounter_type"  
  #belongs_to :provider, -> { where voided: 0 }, class_name: "Person", foreign_key: "provider_id"
  belongs_to :patient, -> { where voided: 0 }

  # TODO, this needs to account for current visit, which needs to account for possible retrospective entry
  scope :current, -> {where('DATE(encounter.encounter_datetime) = CURRENT_DATE()')}


  def after_void(reason = nil)
    unless self.name.upcase == 'ART ADHERENCE'
      self.observations.each do |row| 
        if not row.order_id.blank?
          ActiveRecord::Base.connection.execute <<EOF
            UPDATE drug_order SET quantity = NULL WHERE order_id = #{row.order_id};
EOF
        end rescue nil
        row.void(reason) 
      end rescue []

      self.orders.each do |order|
        order.void(reason) 
      end
    end
  end

  def name
    self.type.name rescue "N/A"
  end
  def date
  	self.encounter_datetime
  end

  def encounter_type_name=(encounter_type_name)
    self.type = EncounterType.find_by_name(encounter_type_name)
    raise "#{encounter_type_name} not a valid encounter_type" if self.type.nil?
  end

  def to_s
    if name == 'REGISTRATION'
      "Patient was seen at the registration desk at #{encounter_datetime.strftime('%I:%M')}" 
    elsif name == 'TREATMENT'
      o = orders.collect{|order| order.to_s}.join("\n")
      o = "No prescriptions have been made" if o.blank?
      o
    elsif name == 'VITALS'
      temp = observations.select {|obs| obs.concept.concept_names.map(&:name).include?("TEMPERATURE (C)") && "#{obs.answer_string}".upcase != 'UNKNOWN' }
      weight = observations.select {|obs| obs.concept.concept_names.map(&:name).include?("WEIGHT (KG)") || obs.concept.concept_names.map(&:name).include?("Weight (kg)") && "#{obs.answer_string}".upcase != '0.0' }
      height = observations.select {|obs| obs.concept.concept_names.map(&:name).include?("HEIGHT (CM)") || obs.concept.concept_names.map(&:name).include?("Height (cm)") && "#{obs.answer_string}".upcase != '0.0' }
      vitals = [weight_str = weight.first.answer_string + 'KG' rescue 'UNKNOWN WEIGHT',
        height_str = height.first.answer_string + 'CM' rescue 'UNKNOWN HEIGHT']
      temp_str = temp.first.answer_string + '°C' rescue nil
      vitals << temp_str if temp_str                          
      vitals.join(', ')
    else  
      observations.collect{|observation| "<b>#{(observation.concept.concept_names.last.name) rescue ""}</b>: #{observation.answer_string}"}.join(", ")
    end  
  end

  def self.statistics(encounter_types, opts={})
    encounter_types = EncounterType.where(['name IN (?)', encounter_types])
    encounter_types_hash = encounter_types.inject({}) {|result, row| result[row.encounter_type_id] = row.name; result }
    rows = self.where(['encounter_type IN (?)', encounter_types.map(&:encounter_type_id)]).where(opts[:conditions]).group("encounter_type").select("count(*) as number, encounter_type")
    return rows.inject({}) {|result, row| result[encounter_types_hash[row['encounter_type']]] = row['number']; result }
  end

  def self.fast_track_patient_encounters(start_date, end_date, page_number)
    fast_track_concept_id = Concept.find_by_name("FAST").concept_id
    yes_concept_id = Concept.find_by_name("YES").concept_id

    fast_track_encounters = Encounter.joins(:observations).where(["DATE(encounter_datetime) >= ? AND
        DATE(encounter_datetime) <= ? AND concept_id =? AND value_coded =?",
        start_date.to_date, end_date.to_date, fast_track_concept_id, yes_concept_id]
    ).paginate(page: page_number, per_page: 20).group("patient_id")

    return fast_track_encounters
  end
  
end
