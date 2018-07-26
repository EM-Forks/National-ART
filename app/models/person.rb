class Person < ActiveRecord::Base

  self.table_name = "person"
  self.primary_key  = "person_id"
  before_save :before_save
  before_create :before_create
  include Openmrs

  cattr_accessor :session_datetime
  cattr_accessor :migrated_datetime
  cattr_accessor :migrated_creator
  cattr_accessor :migrated_location

  has_one :patient, ->{where(voided:0)},class_name: :Patient, foreign_key: :patient_id, dependent: :destroy
  has_many :names, ->{where(voided:0)},class_name: :PersonName, foreign_key: :person_id, dependent: :destroy #, order: 'person_name.preferred DESC'
  has_many :addresses, ->{where(voided:0)}, class_name: :PersonAddress, foreign_key: :person_id, dependent: :destroy #, order: 'person_address.preferred DESC'
  has_many :relationships,->{where(voided:0)}, class_name: :Relationship, foreign_key: :person_a
  has_many :person_attributes,->{where(voided:0)}, class_name: :PersonAttribute, foreign_key: :person_id
  has_many :observations,->{where(voided:0)}, class_name: :Observation, foreign_key: :person_id, dependent: :destroy do
    def find_by_concept_name(name)
      concept_name = ConceptName.find_by_name(name)
      where('concept_id = ?', concept_name.concept_id) rescue []
    end
  end


  def after_void(reason = nil)
    self.patient.void(reason) rescue nil
    self.names.each{|row| row.void(reason) }
    self.addresses.each{|row| row.void(reason) }
    self.relationships.each{|row| row.void(reason) }
    self.person_attributes.each{|row| row.void(reason) }
    # We are going to rely on patient => encounter => obs to void those
  end

  def age(today = Date.today)
    return nil if self.birthdate.nil?

    # This code which better accounts for leap years
    patient_age = (today.year - self.birthdate.year) + ((today.month - self.birthdate.month) + ((today.day - self.birthdate.day) < 0 ? -1 : 0) < 0 ? -1 : 0)

    # If the birthdate was estimated this year, we round up the age, that way if
    # it is March and the patient says they are 25, they stay 25 (not become 24)
    birth_date=self.birthdate
    estimate=self.birthdate_estimated
    patient_age += (estimate && birth_date.month == 7 && birth_date.day == 1  &&
        today.month < birth_date.month && self.date_created.year == today.year) ? 1 : 0
  end

  def age_in_months(today = Date.today)
    years = (today.year - self.birthdate.year)
    months = (today.month - self.birthdate.month)
    (years * 12) + months
  end

  def self.update_date_changed(person_id, today = Date.today)
    ActiveRecord::Base.connection.execute("UPDATE person_address SET date_voided = \"#{today}\" WHERE person_id = #{person_id}")
  end

  def date_addressed_changed
    last_person_address = self.addresses.last
    unless last_person_address.blank?
      date_changed = last_person_address.date_voided
      if date_changed.blank?
        date_created = last_person_address.date_created
        return date_created
      end
      return date_changed
    end
  end

  def dde_doc_id
    patient_identifier_type = PatientIdentifierType.find_by_name("DDE person document ID")
    patient_identifier_type_id = patient_identifier_type.id

    patient_identifier =  PatientIdentifier.where(["identifier_type =? AND patient_id =?",
        patient_identifier_type_id, self.person_id
      ]).last
    return nil if patient_identifier.blank?
    return patient_identifier.identifier
  end

end
