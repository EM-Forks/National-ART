class Patient < ActiveRecord::Base
  before_save :before_save
  before_create :before_create
  self.table_name = "patient"
  self.primary_key ="patient_id"
  include Openmrs

  has_one :person, ->{where(voided: 0)},foreign_key: :person_id
  has_many :patient_identifiers,-> {where(voided: 0)}, foreign_key: :patient_id, dependent: :destroy
  has_many :patient_programs,-> {where(voided:0)}
  has_many :programs, through: :patient_programs
  has_many :relationships,->{where(voided: 0)}, foreign_key: :person_a, dependent: :destroy
  has_many :orders, ->{where(voided:0)}
  #belongs_to :person, ->{where(voided:0)}, foreign_key: :person_id
  has_many :encounters,->{where(voided:0)} do

    def find_by_date(encounter_date)
      encounter_date = Date.today unless encounter_date
      where("encounter_datetime BETWEEN ? AND ?",
        encounter_date.to_date.strftime('%Y-%m-%d 00:00:00'),
        encounter_date.to_date.strftime('%Y-%m-%d 23:59:59')
      ) # Use the SQL DATE function to compare just the date part
    end
  end


  def after_void(reason = nil)
    self.person.void(reason) rescue nil
    self.patient_identifiers.each {|row| row.void(reason) }
    self.patient_programs.each {|row| row.void(reason) }
    self.orders.each {|row| row.void(reason) }
    self.encounters.each {|row| row.void(reason) }
  end

  def current_bp(date = Date.today)
    encounter_id = self.encounters.where("encounter_type = ? AND DATE(encounter_datetime) = ?",
      EncounterType.find_by_name("VITALS").id, date.to_date).last.id rescue nil

    ans = [(Observation.where("encounter_id = ? AND concept_id = ?", encounter_id,
          ConceptName.find_by_name("SYSTOLIC BLOOD PRESSURE").concept_id).last.answer_string.to_i rescue nil),
      (Observation.where("encounter_id = ? AND concept_id = ?", encounter_id,
          ConceptName.find_by_name("DIASTOLIC BLOOD PRESSURE").concept_id).last.answer_string.to_i rescue nil)
    ]
    ans = ans.reject(&:blank?)
  end

  def physical_address
    return PersonAddress.find_by_person_id(self.id, :conditions => "voided = 0").city_village rescue nil
  end

  def name
    "#{self.person.names[0].given_name rescue ''} #{self.person.names[0].family_name rescue ''}"
  end

  def self.duplicates(attributes)
    search_str = ''
    ( attributes.sort || [] ).each do | attribute |
      search_str+= ":#{attribute}" unless search_str.blank?
      search_str = attribute if search_str.blank?
    end rescue []

    return if search_str.blank?
    duplicates = {}
    patients = Patient.find(:all) # AND DATE(date_created >= ?) AND DATE(date_created <= ?)",
    #'2005-01-01'.to_date,'2010-12-31'.to_date])

    ( patients || [] ).each do | patient |
      if search_str.upcase == "DOB:NAME"
        next if patient.name.blank?
        next if patient.person.birthdate.blank?
        duplicates["#{patient.name}:#{patient.person.birthdate}"] = [] if duplicates["#{patient.name}:#{patient.person.birthdate}"].blank?
        duplicates["#{patient.name}:#{patient.person.birthdate}"] << patient
      elsif search_str.upcase == "DOB:ADDRESS"
        next if patient.physical_address.blank?
        next if patient.person.birthdate.blank?
        duplicates["#{patient.name}:#{patient.physical_address}"] = [] if duplicates["#{patient.name}:#{patient.physical_address}"].blank?
        duplicates["#{patient.name}:#{patient.physical_address}"] << patient
      elsif search_str.upcase == "DOB:LOCATION (PHYSICAL)"
        next if patient.person.birthdate.blank?
        next if patient.person.addresses.last.county_district.blank?
        duplicates["#{patient.person.addresses.last.county_district}:#{patient.physical_address}"] = [] if duplicates["#{patient.person.addresses.last.county_district}:#{patient.physical_address}"].blank?
        duplicates["#{patient.person.addresses.last.county_district}:#{patient.physical_address}"] << patient
      elsif search_str.upcase == "ADDRESS:DOB"
        next if patient.person.birthdate.blank?
        next if patient.physical_address.blank?
        if duplicates["#{patient.physical_address}:#{patient.person.birthdate}"].blank?
          duplicates["#{patient.physical_address}:#{patient.person.birthdate}"] = []
        end
        duplicates["#{patient.physical_address}:#{patient.person.birthdate}"] << patient
      elsif search_str.upcase == "ADDRESS:LOCATION (PHYSICAL)"
        next if patient.person.addresses.last.county_district.blank?
        next if patient.physical_address.blank?
        if duplicates["#{patient.physical_address}:#{patient.person.addresses.last.county_district}"].blank?
          duplicates["#{patient.physical_address}:#{patient.person.addresses.last.county_district}"] = []
        end
        duplicates["#{patient.physical_address}:#{patient.person.addresses.last.county_district}"] << patient
      elsif search_str.upcase == "ADDRESS:NAME"
        next if patient.name.blank?
        next if patient.physical_address.blank?
        if duplicates["#{patient.physical_address}:#{patient.name}"].blank?
          duplicates["#{patient.physical_address}:#{patient.name}"] = []
        end
        duplicates["#{patient.physical_address}:#{patient.name}"] << patient
      elsif search_str.upcase == "ADDRESS:LOCATION (PHYSICAL)"
        next if patient.person.addresses.last.county_district.blank?
        next if patient.physical_address.blank?
        if duplicates["#{patient.physical_address}:#{patient.person.addresses.last.county_district}"].blank?
          duplicates["#{patient.physical_address}:#{patient.person.addresses.last.county_district}"] = []
        end
        duplicates["#{patient.physical_address}:#{patient.person.addresses.last.county_district}"] << patient
      elsif search_str.upcase == "DOB:LOCATION (PHYSICAL)"
        next if patient.person.addresses.last.county_district.blank?
        next if patient.person.birthdate.blank?
        if duplicates["#{patient.person.birthdate}:#{patient.person.addresses.last.county_district}"].blank?
          duplicates["#{patient.person.birthdate}:#{patient.person.addresses.last.county_district}"] = []
        end
        duplicates["#{patient.person.birthdate}:#{patient.person.addresses.last.county_district}"] << patient
      elsif search_str.upcase == "LOCATION (PHYSICAL):NAME"
        next if patient.name.blank?
        next if patient.person.addresses.last.county_district.blank?
        if duplicates["#{patient.person.addresses.last.county_district}:#{patient.name}"].blank?
          duplicates["#{patient.person.addresses.last.county_district}:#{patient.name}"] = []
        end
        duplicates["#{patient.person.addresses.last.county_district}:#{patient.name}"] << patient
      elsif search_str.upcase == "ADDRESS:DOB:LOCATION (PHYSICAL):NAME"
        next if patient.name.blank?
        next if patient.person.birthdate.blank?
        next if patient.physical_address.blank?
        next if patient.person.addresses.last.county_district.blank?
        if duplicates["#{patient.name}:#{patient.person.birthdate}:#{patient.physical_address}:#{patient.person.addresses.last.county_district}"].blank?
          duplicates["#{patient.name}:#{patient.person.birthdate}:#{patient.physical_address}:#{patient.person.addresses.last.county_district}"] = []
        end
        duplicates["#{patient.name}:#{patient.person.birthdate}:#{patient.physical_address}:#{patient.person.addresses.last.county_district}"] << patient
      elsif search_str.upcase == "ADDRESS"
        next if patient.physical_address.blank?
        if duplicates[patient.physical_address].blank?
          duplicates[patient.physical_address] = []
        end
        duplicates[patient.physical_address] << patient
      elsif search_str.upcase == "DOB"
        next if patient.person.birthdate.blank?
        if duplicates[patient.person.birthdate].blank?
          duplicates[patient.person.birthdate] = []
        end
        duplicates[patient.person.birthdate] << patient
      elsif search_str.upcase == "LOCATION (PHYSICAL)"
        next if patient.person.addresses.last.county_district.blank?
        if duplicates[patient.person.addresses.last.county_district].blank?
          duplicates[patient.person.addresses.last.county_district] = []
        end
        duplicates[patient.person.addresses.last.county_district] << patient
      elsif search_str.upcase == "NAME"
        next if patient.name.blank?
        if duplicates[patient.name].blank?
          duplicates[patient.name] = []
        end
        duplicates[patient.name] << patient
      end
    end
    hash_to = {}
    duplicates.each do |key,pats |
      next unless pats.length > 1
      hash_to[key] = pats
    end
    hash_to
  end

  def self.merge(patient_id, secondary_patient_id)
    patient = Patient.includes([:patient_identifiers, :patient_programs, {:person => [:names]}]).find(patient_id)
    secondary_patient = Patient.includes([:patient_identifiers, :patient_programs, {:person => [:names]}]).find(secondary_patient_id)
    sec_pt_arv_numbers = PatientIdentifier.where(["patient_id =? AND identifier_type =?",
        secondary_patient_id, PatientIdentifierType.find_by_name('ARV NUMBER').id]).map(&:identifier) rescue []

    national_ids = PatientIdentifier.where(["patient_id =? AND identifier_type =?",
        secondary_patient_id, PatientIdentifierType.find_by_name('National id').id]).map(&:identifier) rescue []

    old_id = PatientIdentifierType.find_by_name("Old Identification Number").id
    national_id = PatientIdentifierType.find_by_name("National id").id

    unless sec_pt_arv_numbers.blank?
      sec_pt_arv_numbers.each do |arv_number|
        ActiveRecord::Base.connection.execute("
          UPDATE patient_identifier SET voided = 1, date_voided=NOW(),voided_by=#{User.current.user_id},
          void_reason = 'merged with patient #{patient_id}'
          WHERE patient_id = #{secondary_patient_id}
          AND identifier = '#{arv_number}'")
      end
    end

    unless national_ids.blank?
      ActiveRecord::Base.connection.execute("
          UPDATE patient_identifier SET identifier_type = #{old_id}, patient_id = #{patient_id} WHERE patient_id = #{secondary_patient_id}
          AND identifier_type = #{national_id}")
    end

    ActiveRecord::Base.transaction do
      secondary_patient.patient_identifiers.each {|r|

        if patient.patient_identifiers.map(&:identifier).each{| i | i.upcase }.include?(r.identifier.upcase)
          ActiveRecord::Base.connection.execute("
          UPDATE patient_identifier SET voided = 1, date_voided=NOW(),voided_by=#{User.current.user_id},
          void_reason = 'merged with patient #{patient_id}'
          WHERE patient_id = #{secondary_patient_id}
          AND identifier_type = #{r.identifier_type}
          AND identifier = '#{r.identifier}'")
        else
          ActiveRecord::Base.connection.execute <<EOF
UPDATE patient_identifier SET patient_id = #{patient_id}
WHERE patient_id = #{secondary_patient_id}
AND identifier_type = #{r.identifier_type}
AND identifier = "#{r.identifier}"
EOF
        end
      }

      secondary_patient.person.names.each {|r|
        if patient.person.names.map{|pn| "#{pn.given_name.upcase rescue ''} #{pn.family_name.upcase rescue ''}"}.include?("#{r.given_name.upcase rescue ''} #{r.family_name.upcase rescue ''}")
          ActiveRecord::Base.connection.execute("
        UPDATE person_name SET voided = 1, date_voided=NOW(),voided_by=#{User.current.user_id},
        void_reason = 'merged with patient #{patient_id}'
        WHERE person_id = #{secondary_patient_id}
        AND person_name_id = #{r.person_name_id}")
        end
      }

      secondary_patient.person.addresses.each {|r|
        if patient.person.addresses.map{|pa| "#{pa.city_village.upcase rescue ''}"}.include?("#{r.city_village.upcase rescue ''}")
          ActiveRecord::Base.connection.execute("
        UPDATE person_address SET voided = 1, date_voided=NOW(),voided_by=#{User.current.user_id},
        void_reason = 'merged with patient #{patient_id}'
        WHERE person_id = #{secondary_patient_id}")
        else
          ActiveRecord::Base.connection.execute <<EOF
UPDATE person_address SET person_id = #{patient_id}
WHERE person_id = #{secondary_patient_id}
AND person_address_id = #{r.person_address_id}
EOF
        end
      }

      secondary_patient.patient_programs.each {|r|
        if patient.patient_programs.map(&:program_id).include?(r.program_id)
          ActiveRecord::Base.connection.execute("
        UPDATE patient_program SET voided = 1, date_voided=NOW(),voided_by=#{User.current.user_id},
        void_reason = 'merged with patient #{patient_id}'
        WHERE patient_id = #{secondary_patient_id}
        AND patient_program_id = #{r.patient_program_id}")
        else
          ActiveRecord::Base.connection.execute <<EOF
UPDATE patient_program SET patient_id = #{patient_id}
WHERE patient_id = #{secondary_patient_id}
AND patient_program_id = #{r.patient_program_id}
EOF
        end
      }

      ActiveRecord::Base.connection.execute("
        UPDATE patient SET voided = 1, date_voided=NOW(),voided_by=#{User.current.user_id},
        void_reason = 'merged with patient #{patient_id}'
        WHERE patient_id = #{secondary_patient_id}")

      ActiveRecord::Base.connection.execute("UPDATE person_attribute SET person_id = #{patient_id} WHERE person_id = #{secondary_patient_id}")
      ActiveRecord::Base.connection.execute("UPDATE person_address SET person_id = #{patient_id} WHERE person_id = #{secondary_patient_id}")
      ActiveRecord::Base.connection.execute("UPDATE encounter SET patient_id = #{patient_id} WHERE patient_id = #{secondary_patient_id}")
      ActiveRecord::Base.connection.execute("UPDATE obs SET person_id = #{patient_id} WHERE person_id = #{secondary_patient_id}")
      ActiveRecord::Base.connection.execute("UPDATE note SET patient_id = #{patient_id} WHERE patient_id = #{secondary_patient_id}")
      #ActiveRecord::Base.connection.execute("UPDATE person SET person_id = #{patient_id} WHERE person_id = #{secondary_patient_id}")
    end
  end

  def self.vl_result_hash(patient)
    encounter_type = EncounterType.find_by_name("REQUEST").id
    viral_load = Concept.find_by_name("Hiv viral load").concept_id
    identifiers = LabController.new.id_identifiers(patient)
    second_line_regimens = patient.second_line_regimens
    national_ids = identifiers
    vl_hash = {}
    results = Lab.find_by_sql(["
        SELECT * FROM Lab_Sample s
        INNER JOIN Lab_Parameter p ON p.sample_id = s.sample_id
        INNER JOIN codes_TestType c ON p.testtype = c.testtype
        INNER JOIN (SELECT DISTINCT rec_id, short_name FROM map_lab_panel) m ON c.panel_id = m.rec_id
        WHERE s.patientid IN (?)
        AND short_name = ?
        AND s.deleteyn = 0
        AND s.attribute = 'pass'", national_ids, 'HIV_viral_load'
      ]).collect do | result |
      [
        result.Sample_ID,
        result.Range,
        result.TESTVALUE,
        result.TESTDATE,
        result.AccessionNum
      ]
    end
    #raise results.inspect

    results.each do |result|

      accession_number = result[0]
      range = result[1]
      vl_result = result[2]
      date_of_test = result[3].to_date rescue 'Unknown'

      vl_hash[accession_number] = {} if vl_hash[accession_number].blank?
      vl_hash[accession_number]["result"] = {} if vl_hash[accession_number]["result"].blank?
      vl_hash[accession_number]["result"] = vl_result
      vl_hash[accession_number]["range"] = range
      vl_hash[accession_number]["date_of_test"] = {} if vl_hash[accession_number]["date_of_sample"].blank?
      vl_hash[accession_number]["date_of_test"] = date_of_test

      vl_lab_sample_obs = Observation.where(["
                        person_id =? AND encounter_type =? AND concept_id =? AND accession_number =?
                        AND value_text LIKE (?)",
          patient.id, encounter_type, viral_load, accession_number.to_i, '%Result given to patient%']
      ).joins(:encounter).last rescue nil


      unless vl_lab_sample_obs.blank?
        vl_hash[accession_number]["result_given"] = {} if vl_hash[accession_number]["result_given"].blank?
        vl_hash[accession_number]["result_given"] = "yes"
        vl_hash[accession_number]["date_result_given"] = {} if vl_hash[accession_number]["date_result_given"].blank?
        vl_hash[accession_number]["date_result_given"] = vl_lab_sample_obs.value_datetime.to_date
      else
        vl_hash[accession_number]["result_given"] = {} if vl_hash[accession_number]["result_given"].blank?
        vl_hash[accession_number]["result_given"] = "no"
        vl_hash[accession_number]["date_result_given"] = {} if vl_hash[accession_number]["date_result_given"].blank?
        vl_hash[accession_number]["date_result_given"] = ""
      end

      switched_to_second_line_obs = Observation.where(["
        person_id =? AND encounter_type =? AND concept_id =? AND accession_number =?
        AND value_text LIKE (?)",patient.id, encounter_type, viral_load, accession_number.to_i,
          '%Patient switched to second line%']).joins(:encounter).last rescue nil

      unless second_line_regimens.blank?
        date_switched = second_line_regimens.first[1]
        date_switched = date_switched.to_date.strftime("%d-%b-%Y") rescue date_switched

        vl_hash[accession_number]["second_line_switch"] = {} if vl_hash[accession_number]["second_line_switch"].blank?
        vl_hash[accession_number]["second_line_switch"] = "yes (#{date_switched})"
      else
        unless switched_to_second_line_obs.blank?
          vl_hash[accession_number]["second_line_switch"] = {} if vl_hash[accession_number]["second_line_switch"].blank?
          vl_hash[accession_number]["second_line_switch"] = "yes"
        else
          vl_hash[accession_number]["second_line_switch"] = {} if vl_hash[accession_number]["second_line_switch"].blank?
          vl_hash[accession_number]["second_line_switch"] = "no"
        end
      end
    end

    return vl_hash.sort_by{|key, value| (value["date_of_sample"].to_date rescue 'Unknown') }.reverse rescue {}
  end

  def self.allergic_to_sulpher(patient, date = Date.today)
    return  Observation.find(Observation.where(["person_id = ? AND concept_id = ?
      AND DATE(obs_datetime) <= ?", patient.id, ConceptName.find_by_name("Allergic to sulphur"
          ).concept_id, date]).order("obs_datetime DESC,date_created DESC").first.id).answer_string.strip.squish rescue ''
  end

  def self.obs_available_in(patient, encounter_array, date = Date.today)
    return Encounter.where(["patient_id = ? AND encounter_type IN (?) AND DATE(encounter_datetime) = ?",
        patient.id, EncounterType.where(["name IN (?)",encounter_array]
        ).map(&:encounter_type_id),date.to_date]).order(
      "encounter_datetime DESC,date_created DESC").first.observations rescue []
  end

  def self.tb_encounter(patient)
    return Encounter.where(["patient_id = ? AND encounter_type = ?",
        patient.id,
        EncounterType.find_by_name("TB visit").id]
    ).order("encounter_datetime DESC,date_created DESC").last rescue nil
  end

  def self.current_hiv_program_state(patient)
    return PatientProgram.where(["patient_id = ? AND program_id = ? AND location.location_id = ? AND date_completed IS NULL",
        patient.id, Program.find_by_concept_id(Concept.find_by_name('HIV PROGRAM').id).id,
        Location.current_health_center.id]).joins(:location).first.patient_states.current.first.program_workflow_state.concept.fullname rescue ''
  end

  def self.hiv_encounter(patient, encounter, date = Date.today)
    return Encounter.includes(:observations).where(["DATE(encounter_datetime) = ? AND patient_id = ? AND encounter_type = ?",
        date.to_date, patient.id, EncounterType.find_by_name(encounter).id]
    ).order("encounter_datetime DESC,date_created DESC")
  end

  def self.concept_set(concept)
    concept_id = ConceptName.find_by_name(concept).concept_id
    set = ConceptSet.where(concept_set_id: concept_id).order('sort_weight')
    symptoms_ids = set.map{|item|next if item.concept.blank? ; item.concept_id }
    return symptoms_ids
  end

  def self.regimen_index(hiv_regimen_map)
    return Regimen.find_by_sql(["select distinct(c.name) as name, r.regimen_index as reg_index from concept_name c
    inner join regimen r on r.concept_id = c.concept_id
    where c.concept_id = ? and  concept_name_type = 'short' limit 1",hiv_regimen_map]).map{|regimen| regimen.reg_index}
  end

  def date_started_art
    amount_dispensed = ConceptName.find_by_name('Amount dispensed').concept_id
    eal_dispension_date =  ActiveRecord::Base.connection.select_value("SELECT MIN(obs_datetime) 
      FROM obs WHERE concept_id = #{amount_dispensed} AND person_id = #{self.patient_id}").to_date rescue nil

    return  ActiveRecord::Base.connection.select_value("SELECT date_antiretrovirals_started(#{self.patient_id},
      '#{eal_dispension_date.to_date.to_s}');").to_date rescue nil
  end

  def self.type_of_hiv_confirmatory_test(patient, session_date = Date.today)
    hiv_confirmatory_test_concept_id = Concept.find_by_name('CONFIRMATORY HIV TEST TYPE').concept_id

    hiv_confirmatory_answer_string = patient.person.observations.where(["DATE(obs_datetime) <= ? AND concept_id =?",
        session_date, hiv_confirmatory_test_concept_id]
    ).last.answer_string.squish.upcase rescue nil

    return hiv_confirmatory_answer_string
  end

  def self.date_of_hiv_clinic_registration(patient, session_date = Date.today)
    encounter_type_id = EncounterType.find_by_name("HIV CLINIC REGISTRATION").encounter_type_id
    hiv_clinic_reg_enc = patient.encounters.where(["encounter_type =? AND DATE(encounter_datetime) < ?",
        encounter_type_id, session_date]).last

    unless hiv_clinic_reg_enc.blank?
      reg_date = (hiv_clinic_reg_enc.encounter_datetime.to_date rescue hiv_clinic_reg_enc.encounter_datetime)
      return reg_date
    end

    return ""
  end

  def self.cpt_prescribed_in_the_last_prescription?(patient, session_date = Date.today)
    last_order_date = patient.orders.where(["DATE(encounter_datetime) < ?", session_date]
    ).joins(:encounter).last.encounter.encounter_datetime.to_date rescue nil
    return false if last_order_date.blank?
    last_orders = patient.orders.where(["DATE(encounter_datetime) =?",
        last_order_date]).joins(:encounter)

    last_orders.each do |order|
      drug_name = order.drug_order.drug.name rescue nil
      next if drug_name.blank?
      if drug_name.match(/COTRI/i)
        return true
        break
      end
    end

    return false
  end

  def self.ipt_prescribed_in_the_last_prescription?(patient, session_date = Date.today)
    last_order_date = patient.orders.where(["DATE(encounter_datetime) < ?", session_date]
    ).joins(:encounter).last.encounter.encounter_datetime.to_date rescue nil
    return false if last_order_date.blank?
    last_orders = patient.orders.where(["DATE(encounter_datetime) =?",
        last_order_date]).joins(:encounter)

    last_orders.each do |order|
      drug_name = order.drug_order.drug.name rescue nil
      next if drug_name.blank?
      if drug_name.match(/ISONIAZID/i)
        return true
        break
      end
    end

    return false
  end

  def self.history_of_side_effects(patient, session_date = Date.today)
    side_effects = {}
    encounter_type_id = EncounterType.find_by_name("HIV CLINIC CONSULTATION").encounter_type_id
    side_effects_concept_id = Concept.find_by_name("MLW ART SIDE EFFECTS").concept_id
    
    hiv_clinic_consultation_encounters = patient.encounters.where(["encounter_type =? AND
                                         DATE(encounter_datetime) <= ?", encounter_type_id,
        session_date.to_date])

    hiv_clinic_consultation_encounters.each do |enc|
      encounter_datetime = enc.encounter_datetime.to_date.strftime("%d/%b/%Y")
      observation_answers = enc.observations.where(["concept_id =?",
          side_effects_concept_id]).collect{|o|o.answer_string.squish}.compact
      side_effects[encounter_datetime] = observation_answers unless observation_answers.blank?
    end

    return side_effects
  end
=begin
side_effects_concept_id = Concept.find_by_name("MALAWI ART SIDE EFFECTS").concept_id
    symptom_present_conept_id = Concept.find_by_name("SYMPTOM PRESENT").concept_id

    @side_effects_answers = @patient.person.observations.find(:all, :conditions => ["concept_id IN (?) AND
        DATE(obs_datetime) =?", [side_effects_concept_id, symptom_present_conept_id], session_date]
    ).collect{|o|o.answer_string.squish}
=end

  def self.contraindications(patient, session_date = Date.today)
    side_effects_concept_id = Concept.find_by_name("MALAWI ART SIDE EFFECTS").concept_id
    symptom_present_concept_id = Concept.find_by_name("SYMPTOM PRESENT").concept_id

    encounter_type_id = EncounterType.find_by_name("HIV CLINIC CONSULTATION").encounter_type_id
    encounter = patient.encounters.where(["encounter_type =? AND
        DATE(encounter_datetime) <= ?", encounter_type_id, session_date]).first
    return [] if encounter.blank?

    contraindications = patient.person.observations.where(["concept_id IN (?) AND
        DATE(obs_datetime) <= ? AND encounter_id =?", [side_effects_concept_id, symptom_present_concept_id],
        session_date, encounter.id]
    ).collect{|o|o.answer_string.squish}

    return contraindications
  end

  def self.date_of_first_hiv_clinic_enc(patient, session_date = Date.today)
    
    encounter_type_id = EncounterType.find_by_name("HIV CLINIC CONSULTATION").encounter_type_id
    encounter_datetime = patient.encounters.where(["encounter_type =? AND
        DATE(encounter_datetime) <= ?", encounter_type_id, session_date]
    ).first.encounter_datetime.to_date.strftime("%d/%b/%Y") rescue nil

    return encounter_datetime
  end

  def self.todays_side_effects(patient, session_date = Date.today)
    side_effects_concept_id = Concept.find_by_name("MALAWI ART SIDE EFFECTS").concept_id
    symptom_present_conept_id = Concept.find_by_name("SYMPTOM PRESENT").concept_id

    side_effects_observations = patient.person.observations.where(["concept_id IN (?) AND
        DATE(obs_datetime) = ?", [side_effects_concept_id, symptom_present_conept_id], session_date])

    side_effects_contraindications = []
    side_effects_observations.each do |obs|
      next if !obs.obs_group_id.blank?
      child_obs = Observation.where(["obs_group_id = ?", obs.obs_id]).last
      unless child_obs.blank?
        answer_string = child_obs.answer_string.squish
        next if answer_string.match(/NO/i)
        side_effects_contraindications << child_obs.concept.fullname
      end
    end

    return side_effects_contraindications
  end

  def self.side_effects_obs_ever(patient, session_date = Date.today)
    side_effects_concept_id = Concept.find_by_name("MALAWI ART SIDE EFFECTS").concept_id
    symptom_present_conept_id = Concept.find_by_name("SYMPTOM PRESENT").concept_id

    side_effects_observations = patient.person.observations.where(["concept_id IN (?) AND
        DATE(obs_datetime) <= ?", [side_effects_concept_id, symptom_present_conept_id], session_date])
    side_effects_obs_ever = []
    side_effects_observations.each do |obs|
      next if !obs.obs_group_id.blank?
      child_obs = Observation.where(["obs_group_id = ?", obs.obs_id]).last
      unless child_obs.blank?
        answer_string = child_obs.answer_string.squish
        next if answer_string.match(/NO/i)
        side_effects_obs_ever << obs
        #side_effects_ever << child_obs.concept.fullname
      end
    end

    return side_effects_obs_ever
  end

  def self.previous_weight(patient, session_date)
    weight_concept_id = Concept.find_by_name("WEIGHT").concept_id

    previous_patient_weight = patient.person.observations.where(["concept_id =? AND
        DATE(obs_datetime) < ?", weight_concept_id, session_date]
    ).last.answer_string.squish rescue 0

    return previous_patient_weight
  end

  def self.ever_had_dispensations(patient, session_date)
    dispensing_enc_type_id =  EncounterType.find_by_name('DISPENSING').id
    dispensation_encounters = patient.encounters.where(["encounter_type =? AND
        (DATE(encounter_datetime) < ? OR DATE(encounter_datetime) > ?)", dispensing_enc_type_id, session_date, session_date])
    return true unless dispensation_encounters.blank?
    return false
  end

  def self.latest_outcome_date(patient)
    outcome_dates = []
    hiv_program_id = Program.find_by_name("HIV PROGRAM").id
    hiv_program = patient.patient_programs.where(["program_id = ?", hiv_program_id]).last

    hiv_program.patient_states.each do |ps|
      outcome_dates << ps.start_date
    end rescue nil
    
    return outcome_dates.last
  end

  def self.states(patient)
    hiv_program_id = Program.find_by_name("HIV PROGRAM").id
    hiv_program = patient.patient_programs.find(:last, :conditions => ["program_id = ?", hiv_program_id])
    return hiv_program.patient_states
  end

  def self.has_inconsistency_outcome_dates?(patient)
    hiv_program_id = Program.find_by_name("HIV PROGRAM").id
    hiv_program = patient.patient_programs.where(["program_id = ?", hiv_program_id]).last
    outcome_dates = hiv_program.patient_states.collect{|ps|[ps.start_date, ps.end_date]} rescue []
    inconsistency_outcome = false

    death_date = patient.person.death_date.to_date rescue patient.person.death_date
    outcome_dates.each do |dates|
      start_date = dates[0].to_date rescue dates[0]
      end_date = dates[1].to_date rescue dates[1]

      if start_date > end_date
        inconsistency_outcome = true
      end unless end_date.blank?

      unless death_date.blank?
        if death_date < start_date
          inconsistency_outcome = true
        end
      end

    end

    return inconsistency_outcome
  end

  def second_line_regimens
	  regimen_category = Concept.find_by_name("Regimen Category")

    regimen_observations = Observation.where(["concept_id = ? AND
        person_id = ?", regimen_category.id, self.patient_id])

    second_line_regimen_indices = ["7A","8A","9P", "9A"]
    data = {}
    regimen_observations.each do |obs|
      regimen = obs.answer_string.squish.upcase rescue nil
      obs_datetime = obs.obs_datetime
      next if regimen.blank?
      if second_line_regimen_indices.include?(regimen.to_s)
        if data[regimen].blank?
          data[regimen] = {}
          data[regimen] = obs_datetime.to_date.strftime("%d/%b/%Y")
        end
      end
    end
    
    return data
  end

  def tb_status(encounter_datetime)
    tb_status_concept_id = ConceptName.find_by_name('TB STATUS').concept_id
    tb_obs = Observation.where(["concept_id =? AND DATE(encounter_datetime) =? AND patient_id =?",
        tb_status_concept_id, encounter_datetime.to_date,
        self.patient_id]).joins(:encounter).last

    answer_string = tb_obs.answer_string.squish rescue ""
    return answer_string
  end

  def regimen(encounter_datetime)
    regimen_category_concept_id = Concept.find_by_name("Regimen Category").concept_id

    regimen_obs = Observation.where(["concept_id =? AND
        DATE(encounter_datetime) =? AND patient_id =?", regimen_category_concept_id, encounter_datetime.to_date, self.patient_id]
    ).joins(:encounter).last
    answer_string = regimen_obs.answer_string.squish rescue ""
    return answer_string
  end

  def vl_result(encounter_datetime)
    identifiers = LabController.new.id_identifiers(self)
    national_ids = identifiers


    results = Lab.find_by_sql(["
        SELECT * FROM Lab_Sample s
        INNER JOIN Lab_Parameter p ON p.sample_id = s.sample_id
        INNER JOIN codes_TestType c ON p.testtype = c.testtype
        INNER JOIN (SELECT DISTINCT rec_id, short_name FROM map_lab_panel) m ON c.panel_id = m.rec_id
        WHERE s.patientid IN (?)
        AND short_name = ?
        AND s.deleteyn = 0
        AND s.attribute = 'pass'", national_ids, 'HIV_viral_load'
      ]).collect{ | result |result.Range.to_s + " " + result.TESTVALUE.to_s}
    
    return results
  end

  def adherence(encounter_datetime)
    drug_order_adherence_concept_id = Concept.find_by_name("DRUG ORDER ADHERENCE").concept_id

    regimen_obs = Observation.where(["concept_id =? AND
        DATE(encounter_datetime) =? AND patient_id =?", drug_order_adherence_concept_id, encounter_datetime.to_date, self.patient_id]
    ).joins(:encounter).last
    answer_string = regimen_obs.answer_string.squish rescue ""
    return answer_string
  end

  def side_effects(encounter_datetime)
    side_effects_concept_id = Concept.find_by_name("MALAWI ART SIDE EFFECTS").concept_id
    symptom_present_conept_id = Concept.find_by_name("SYMPTOM PRESENT").concept_id

    side_effects_observations = self.person.observations.where(["concept_id IN (?) AND DATE(encounter_datetime) =?",
        [side_effects_concept_id, symptom_present_conept_id], encounter_datetime.to_date]
    ).joins(:encounter)

    side_effects = []
    side_effects_observations.each do |obs|
      next if !obs.obs_group_id.blank?
      child_obs = Observation.where(["obs_group_id = ?", obs.obs_id]).last

      unless child_obs.blank?
        answer_string = child_obs.answer_string.squish
        next if answer_string.match(/NO/i)
        side_effects << child_obs.concept.fullname
      end
    end

    return side_effects.join(", ")
  end

  def hypertension(encounter_datetime)
    bp = self.current_bp(encounter_datetime.to_date)
    return "" if bp.blank?
    return bp[0].to_s + "/" + bp[1].to_s
  end

  #################################################################

  def gender
    self.person.gender rescue nil
  end
    
  def age(today = Date.today)
    return nil if self.person.birthdate.nil?

    # This code which better accounts for leap years
    patient_age = (today.year - self.person.birthdate.year) + ((today.month -
          self.person.birthdate.month) + ((today.day - self.person.birthdate.day) < 0 ? -1 : 0) < 0 ? -1 : 0)

    # If the birthdate was estimated this year, we round up the age, that way if
    # it is March and the patient says they are 25, they stay 25 (not become 24)
    birth_date=self.person.birthdate
    estimate=self.person.birthdate_estimated==1
    patient_age += (estimate && birth_date.month == 7 && birth_date.day == 1 &&
        today.month < birth_date.month && self.person.date_created.year == today.year) ? 1 : 0
  end
    
  def eligible_for_htn_screening(date = Date.today)
    threshold = CoreService.get_global_property_value("htn.screening.age.threshold").to_i
    sbp_threshold = CoreService.get_global_property_value("htn_systolic_threshold").to_i
    dbp_threshold = CoreService.get_global_property_value("htn_diastolic_threshold").to_i

    if (self.age(date) >= threshold || self.programs.map{|x| x.name}.include?("HYPERTENSION PROGRAM"))

      htn_program = Program.find_by_name("HYPERTENSION PROGRAM")

      patient_program = enrolled_on_program(htn_program.id,date,false)

      if patient_program.blank?
        #When patient has no HTN program
        last_check = last_bp_readings(date)

        if last_check.blank?
          return true #patient has never had their BP checked
        elsif ((last_check[:sbp].to_i >= sbp_threshold || last_check[:dbp].to_i >= dbp_threshold))
          return true #patient had high BP readings at last visit
        elsif((date.to_date - last_check[:max_date].to_date).to_i >= 365 )
          return true # 1 Year has passed since last check
        else
          return false
        end
      else
        #Get plan

        plan_concept = Concept.find_by_name('Plan').id
        plan = Observation.where(["person_id = ? AND concept_id = ? AND obs_datetime <= ?",self.id, plan_concept,
            date.to_date.strftime('%Y-%m-%d 23:59:59')]).order("obs_datetime DESC").first
        if plan.blank?
          return true
        else
          if plan.value_text.match(/ANNUAL/i)
            if ((date.to_date - plan.obs_datetime.to_date).to_i >= 365 )
              return true #patient on annual screening and time has elapsed
            else
              return false #patient was screen but a year has not passed
            end
          else
            return true #patient requires active screening
          end
        end

      end
    else
      return false
    end

  end

  def bp_normal()
    sbp_threshold = CoreService.get_global_property_value("htn_systolic_threshold").to_i
    dbp_threshold = CoreService.get_global_property_value("htn_diastolic_threshold").to_i

    diastolic = Observation.where(["person_id = ? AND concept_id = ? AND obs_datetime = ?",
        self.id,Concept.find_by_name("diastolic blood pressure").concept_id,
        Date.today]).last
    systolic = Observation.where(["person_id = ? AND concept_id = ? AND obs_datetime = ?",
        self.id,Concept.find_by_name("systolic blood pressure").concept_id,
        Date.today]).last
    if (diastolic.blank? || systolic.blank?)
      raise "Patient has no BP measurements".to_s
    else
      if (diastolic.value_text.to_i >= dbp_threshold || systolic.value_text.to_i >= sbp_threshold)
        false
      else
        true
      end
    end
  end

  def on_hypertensive_medicine()

  end

  def patient_blood_presure(date = Date.today)
    sbp_concept = Concept.find_by_name('Systolic blood pressure').id
    dbp_concept = Concept.find_by_name('Diastolic blood pressure').id
    plan_concept = Concept.find_by_name('Plan').id

    sbp_data = {}
    dbp_data = {}
    plan_data = {}
    visits = []

    sbp_obs = Observation.find_by_sql("
        SELECT * FROM obs WHERE concept_id = #{sbp_concept} AND person_id = #{self.id} AND voided = 0
        AND obs_datetime <= '#{date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      ")

    dbp_obs = Observation.find_by_sql("
        SELECT * FROM obs WHERE concept_id = #{dbp_concept} AND person_id = #{self.id} AND voided = 0
        AND obs_datetime <= '#{date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      ")

    plan_obs = Observation.find_by_sql("
        SELECT * FROM obs WHERE concept_id = #{plan_concept} AND person_id = #{self.id} AND voided = 0
        AND obs_datetime <= '#{date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      ")

    sbp_obs.each do |obs|
      date = obs.obs_datetime.strftime('%d-%b-%Y')
      next if obs.value_numeric.blank?
      sbp_data[date] = obs.value_numeric.to_i
    end

    dbp_obs.each do |obs|
      date = obs.obs_datetime.strftime('%d-%b-%Y')
      next if obs.value_numeric.blank?
      dbp_data[date] = obs.value_numeric.to_i
    end

    plan_obs.each do |obs|
      date = obs.obs_datetime.strftime('%d-%b-%Y')
      plan_data[date] = obs.value_text
    end

    sbp_data.each do |date, sbp|
      dbp = dbp_data[date]
      plan = plan_data[date]
      plan = "" if plan.blank?
      next if dbp.blank?
      visits << {"date" => date, "systolic" => sbp, "diastolic" => dbp, "grade" => bp_grade(sbp, dbp), "plan" => plan,  "drugs" => "None"}
    end
    #visits << {"date" => record.obs_datetime.strftime('%d-%b-%Y'), "systolic" => record["SBP"],"grade" => bp_grade(record["SBP"],record["DBP"]),
    #"diastolic" => record["DBP"], "plan" => (record["plan"].blank? ? "" : record["plan"]), "drugs" => "None"}

    return visits
  end


  def bp_management_trail(date = Date.today)
=begin
      visits = []

      sbp_concept = Concept.find_by_name('Systolic blood pressure').id
      dbp_concept = Concept.find_by_name('Diastolic blood pressure').id
      plan_concept = Concept.find_by_name('Plan').id

      records = Observation.find_by_sql("SELECT  DISTINCT o.encounter_id,o.person_id,DATE(o.obs_datetime) as obs_datetime,
                                       (SELECT value_numeric FROM obs WHERE encounter_id = o.encounter_id
                                       AND concept_id = #{sbp_concept} AND person_id = o.person_id AND voided = 0 LIMIT 1) AS SBP,
                                       (SELECT value_numeric FROM obs WHERE encounter_id = o.encounter_id
                                       AND concept_id = #{dbp_concept} AND person_id = o.person_id AND voided = 0 LIMIT 1) AS DBP,
                                       (SELECT value_text FROM obs WHERE concept_id = #{plan_concept} AND person_id = o.person_id
                                       AND obs_datetime BETWEEN DATE_FORMAT(o.obs_datetime, '%Y-%m-%d 00:00:00') AND
                                       DATE_FORMAT(o.obs_datetime, '%Y-%m-%d 23:59:59') AND voided = 0 LIMIT 1) AS plan
                                       FROM obs as o WHERE o.person_id = #{self.id} AND o.voided = 0 AND obs_datetime <=
                                       '#{date.to_date.strftime('%Y-%m-%d 23:59:59')}' HAVING SBP IS NOT NULL
                                       AND DBP IS NOT NULL ORDER BY o.obs_datetime DESC, o.encounter_id DESC").each do |record|
        #visits[record.obs_datetime.strftime('%d-%b-%Y')] = [] if visits[record.obs_datetime.strftime('%d-%b-%Y')].blank?
        visits << {"date" => record.obs_datetime.strftime('%d-%b-%Y'), "systolic" => record["SBP"],"grade" => bp_grade(record["SBP"],record["DBP"]),
          "diastolic" => record["DBP"], "plan" => (record["plan"].blank? ? "" : record["plan"]), "drugs" => "None"}
      end
return visits
=end
    patient_blood_presure(date)
  end

  def current_bp_drugs(date = Date.today)
    medication_concept = ConceptName.find_by_name("HYPERTENSION DRUGS").concept_id
    dispensing_concept = ConceptName.find_by_name("AMOUNT DISPENSED").concept_id
    drug_concept_ids = ConceptSet.where(['concept_set = ?', medication_concept]).map(&:concept_id)
    drugs = Drug.where(["concept_id IN (?)", drug_concept_ids])

    prev_date = Encounter.joins("INNER JOIN obs ON encounter.encounter_id = obs.encounter_id").where(
      ["encounter.patient_id = ? AND encounter.voided = 0 AND value_drug IN (?) AND DATE(encounter.encounter_datetime) <=?
        AND encounter.encounter_type = ? AND obs.value_drug  IN (?)", self.id, drugs.map(&:drug_id), date,
        EncounterType.find_by_name("DISPENSING").id, drugs.map(&:drug_id)]
    ).select(["encounter_datetime"]).last.encounter_datetime.to_date rescue nil

    return [] if prev_date.blank?
    result = Encounter.find_by_sql(["SELECT obs.value_drug FROM encounter INNER JOIN obs ON obs.encounter_id = encounter.encounter_id
      			WHERE encounter.voided = 0 AND encounter.patient_id = ? AND obs.value_drug IN (?) AND obs.concept_id = ? AND encounter.encounter_type = ? AND DATE(encounter.encounter_datetime) = ?
        ", self.id, drugs.map(&:drug_id), dispensing_concept, EncounterType.find_by_name("DISPENSING").id, prev_date]).map(&:value_drug).uniq  rescue []


=begin
      result = DrugOrder.all(:select => ["drug_inventory_id"], :joins => "
                INNER JOIN orders ON orders.order_id = drug_order.order_id AND orders.patient_id = #{self.id}
                INNER JOIN encounter ON orders.encounter_id = encounter.encounter_id
                INNER JOIN obs ON obs.encounter_id = encounter.encounter.encounter_id
                ",
                     :conditions => ["obs.concept_id = ? drug_inventory_id IN (?) AND DATE(encounter.encounter_datetime) = ?",
                                     drugs.map(&:drug_id), prev_date]).map(&:drug_inventory_id).uniq
=end
    result = result.collect{|drug_id| Drug.find(drug_id).name}
  end

  def enrolled_on_program( program_id, date = DateTime.now, create = false)
    #patient_id
    program = PatientProgram.where(["patient_id = ? AND program_id = ? AND date_enrolled <= ?",
        self.id, program_id, date.strftime("%Y-%m-%d 23:59:59")]).last
#raise self.id.inspect
 
    if program.blank? and create
      ActiveRecord::Base.transaction do
        program = PatientProgram.create({:program_id => program_id, :date_enrolled => date,
            :patient_id => self.id})
        alive_state = ProgramWorkflowState.where(["program_workflow_id = ? AND concept_id = ?",
            ProgramWorkflow.where(["program_id = ?", program_id]).first.id, Concept.find_by_name("Alive").id]).first.id
        PatientState.create(:patient_program_id => program.id, :start_date => date,:state => alive_state )
      end
    end

    program
  end

  def last_bp_readings(date)
    sbp_concept = Concept.find_by_name('Systolic blood pressure').id
    dbp_concept = Concept.find_by_name('Diastolic blood pressure').id
    patient_id = self.id

    latest_date = Observation.find_by_sql("
      SELECT MAX(obs_datetime) AS date FROM obs
      WHERE person_id = #{patient_id}
        AND voided = 0
        AND concept_id IN (#{sbp_concept}, #{dbp_concept})
        AND obs_datetime <= '#{date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      ").last.date.to_date rescue nil

    return nil if latest_date.blank?

    sbp = Observation.find_by_sql("
        SELECT * FROM obs
        WHERE person_id = #{patient_id}
          AND voided = 0
          AND concept_id = #{sbp_concept}
          AND obs_datetime BETWEEN '#{latest_date.to_date.strftime('%Y-%m-%d 00:00:00')}' AND '#{latest_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      ").last.value_numeric rescue nil

    dbp = Observation.find_by_sql("
        SELECT * FROM obs
        WHERE person_id = #{patient_id}
          AND voided = 0
          AND concept_id = #{dbp_concept}
          AND obs_datetime BETWEEN '#{latest_date.to_date.strftime('%Y-%m-%d 00:00:00')}' AND '#{latest_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      ").last.value_numeric rescue nil

    return {:patient_id => patient_id, :max_date => latest_date, :sbp => sbp, :dbp => dbp}
  end

  def drug_notes(date = Date.today)
    notes_concept = sbp_concept = Concept.find_by_name('Notes').id
    drug_ids = ["HCZ (25mg tablet)", "Amlodipine (5mg tablet)", "Amlodipine (10mg tablet)",
      "Enalapril (5mg tablet)", "Enalapril (10mg tablet)",
      "Atenolol (50mg tablet)", "Atenolol (100mg tablet)"].collect{|name| Drug.find_by_name(name).id}
    data = Observation.find_by_sql(["SELECT value_text, value_drug, obs_datetime FROM encounter INNER JOIN obs ON obs.encounter_id = encounter.encounter_id
				WHERE encounter.encounter_type = (SELECT encounter_type_id FROM encounter_type WHERE name = 'HYPERTENSION MANAGEMENT' LIMIT 1)
				AND encounter.patient_id = ?
				AND DATE(encounter.encounter_datetime) <= ?
				AND obs.concept_id = ?
				AND obs.value_drug IN (?)
				AND encounter.voided = 0
        ", self.id, date.to_date, notes_concept, drug_ids])
    result = {}
    map = {
      "HCZ (25mg tablet)" => "HCZ",
      "Amlodipine (5mg tablet)" => "Amlodipine",
      "Amlodipine (10mg tablet)" => "Amlodipine",
      "Enalapril (5mg tablet)" => "Enalapril",
      "Enalapril (10mg tablet)" => "Enalapril",
      "Atenolol (50mg tablet)" => "Atenolol",
      "Atenolol (100mg tablet)" => "Atenolol"
    }
    data.each do |obj|
      drug_name = Drug.find(obj.value_drug).name rescue nil
      name = map[drug_name]
      next if drug_name.blank? || name.blank?

      notes = obj.value_text
      date = obj.obs_datetime.to_date

      result[name] = {} if result[name].blank?
      result[name][date] = [] if result[name][date].blank?
      result[name][date] << notes
    end
    return result
  end

  def pregnancy_status(date = Date.today)
    pregnant = (Observation.where(["person_id = ? AND voided = 0 AND concept_id = ? AND DATE(obs_datetime) = ?",self.id,
          ConceptName.find_by_name("IS PATIENT PREGNANT?").concept_id, (date.to_date)]
      ).last.answer_string.downcase.strip rescue nil) == "yes"

    if pregnant
      return "Patient is pregnant"
    end

    answer = (Observation.where(["person_id = ? AND voided = 0 AND concept_id = ? AND DATE(obs_datetime) = ?",self.id,
          ConceptName.find_by_name("Why does the woman not use birth control").concept_id,
          (date.to_date)]).last.answer_string.upcase.strip rescue nil)

    if answer == "PATIENT WANTS TO GET PREGNANT"
      return "Patient wants to get pregnant"
    elsif answer == "AT RISK OF UNPLANNED PREGNANCY"
      return "At Risk of Unplanned Pregnancy"
    end
  end

  def current_risk_factors(date = Date.today)
    encounter_type = EncounterType.find_by_name("MEDICAL HISTORY").id
    concept_id = ConceptName.find_by_name("HYPERTENSION RISK FACTORS").concept_id
    yes_concept_id = ConceptName.find_by_name("YES").concept_id
    concept_ids = ConceptSet.where(["concept_set =?", concept_id]).collect{|set| set.concept.id}
    current_risk_factors = []
    encounter_id = Encounter.find_by_sql(["SELECT encounter_id FROM encounter
 					WHERE encounter.voided = 0 AND encounter.patient_id = ? AND encounter_datetime <= ?
	 					AND	encounter.encounter_type = ? ORDER BY encounter_datetime DESC,encounter_id DESC  LIMIT 1",
        self.id,date.strftime("%Y-%m-%d 23:59:59"), encounter_type]).first.id rescue nil

    if encounter_id.present?
      current_risk_factors = Observation.where(["encounter_id = ? AND concept_id IN (?)
	 							AND (value_coded = ? OR value_text = 'YES')",
          encounter_id, concept_ids, yes_concept_id]).collect{|o| o.concept.concept_names.first.name.strip}
    end
    current_risk_factors
  end

  def were_htn_risk_factors_captured?(date)
    encounters = Encounter.where(["patient_id = ? AND encounter_datetime <= ? AND encounter_type = ?",
        self.id,date.strftime("%Y-%m%d 23:59:59"),EncounterType.find_by_name("MEDICAL HISTORY").id]).collect{|x|x.id}

    return false if encounters.blank?

    risk_factors = ConceptSet.where(["concept_set =?", ConceptName.find_by_name("HYPERTENSION RISK FACTORS").concept_id]).collect{|set| set.concept.id}

    encounter = Observation.find_by_sql(["SELECT DISTINCT encounter_id FROM obs
										WHERE encounter_id in (?) AND concept_id in (?) AND
										person_id = ? AND voided = 0 LIMIT 1",encounters, risk_factors, self.id])

    if encounter.blank?
      return false
    else
      return true
    end
  end

  def bp_grade(sbp, dbp)

    if (sbp.to_i < 140 ) && (dbp.to_i < 90)
      return "normal"
    elsif ((sbp.to_i >= 140 && sbp.to_i < 160) || (dbp.to_i >= 100 && dbp.to_i < 110))
      return "grade 1"
    elsif (sbp.to_i >= 180 && dbp.to_i > 110) || sbp.to_i >= 180
      return "grade 3"
    elsif ((sbp.to_i >= 160 && sbp.to_i < 180) || (dbp.to_i >= 110 ))
      return "grade 2"
    end
  end

  def normatensive(trail)

    dates_checked = 0
    normal_bp = 0
    dates = []
    (0..2).each do |day|
      return false if trail[day].blank?

      if trail[day]["diastolic"].to_i < 90 && trail[day]["systolic"].to_i < 140 && !dates.include?(trail[day]["date"])
        normal_bp += 1
      end
      dates_checked +=1 if !dates.include?(trail[day]["date"])
      dates << trail[day]["date"] if !dates.include?(trail[day]["date"])

      break if dates_checked == 2 && normal_bp == 2
    end

    if dates_checked == 2 && normal_bp == 2
      return true
    else
      return false
    end
  end

  def drug_use_history(date = Date.today)
    past_drugs = ""
    bp_drug_use_history = Observation.where(["person_id =? AND concept_id =? AND DATE(obs_datetime) =?", self.id,
        Concept.find_by_name('DRUG USE HISTORY').id, date]).last

    unless bp_drug_use_history.blank?
      past_drugs = bp_drug_use_history.value_text
    end

    return past_drugs
  end
end
