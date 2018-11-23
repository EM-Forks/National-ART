class HtnEncounterController < ApplicationController
  def index
  end

  def vitals

    patient = Patient.find(params[:patient_id])
    @patient = patient
		date = session[:datetime].blank? ? Date.today : session[:datetime]
    @patient_eligible = patient.eligible_for_htn_screening(date.to_date)
    @patient_bean = PatientService.get_patient(@patient.person)
    if session[:datetime]
      @retrospective = true
    else
      @retrospective = false
    end
    #@ask_blood_pressure = patient.eligible_for_htn_diagnosis
    @current_height = PatientService.get_patient_attribute_value(@patient, "current_height")
    @min_weight = PatientService.get_patient_attribute_value(@patient, "min_weight")
    @max_weight = PatientService.get_patient_attribute_value(@patient, "max_weight")
    @min_height = PatientService.get_patient_attribute_value(@patient, "min_height")
    @max_height = PatientService.get_patient_attribute_value(@patient, "max_height")
    @user = current_user
    @treatment_status = [
      ['Yes', 'BP Drugs started'],
      ['No', 'Not on BP Drugs']
    ]
    @bp_treatment_info_available = false
    bp_treatment_status = Observation.where(["person_id =? AND
        concept_id =? AND voided=0", params[:patient_id], Concept.find_by_name("TREATMENT STATUS").id]).last
    unless bp_treatment_status.blank?
      @bp_treatment_info_available = true
    end
    @patient_transfer_in  = false
    patient_transfer_in = patient.person.observations.recent(1).question("HAS TRANSFER LETTER").all rescue nil
    @patient_transfer_in = true unless patient_transfer_in.blank?
  end

  def bp_alert

    @patient = Patient.find(params[:patient_id])
    @patient_bean = PatientService.get_patient(@patient.person)
    @bp = @patient.current_bp((session[:datetime] || Time.now()))
    @patient_pregnant = false

    if (@patient.gender == "F")
      @patient_pregnant = true if @patient.pregnancy_status((session[:datetime] || Time.now())) == "Patient is pregnant"
    end

    @patient_on_bp_drugs = false
    treatment_status_concept_id = Concept.find_by_name("TREATMENT STATUS").id
    bp_drugs_started = Observation.where(["person_id =? AND concept_id =? AND value_text REGEXP ?", params[:patient_id], treatment_status_concept_id,
        "BP Drugs started"]).last
    @next_task_to_do = "/htn_encounter/bp_management?patient_id=#{@patient.id}"
    unless bp_drugs_started.blank?
      @patient_on_bp_drugs = true
    end
    
    session[:bp_alert] = @patient.id
  end

  def vitals_confirmation
    @patient = Patient.find(params[:patient_id])
    @patient_bean = PatientService.get_patient(@patient.person)
    if session[:datetime]
      @retrospective = true
    else
      @retrospective = false
    end
    #@ask_blood_pressure = patient.eligible_for_htn_diagnosis
    @current_height = PatientService.get_patient_attribute_value(@patient, "current_height")
    @min_weight = PatientService.get_patient_attribute_value(@patient, "min_weight")
    @max_weight = PatientService.get_patient_attribute_value(@patient, "max_weight")
    @min_height = PatientService.get_patient_attribute_value(@patient, "min_height")
    @max_height = PatientService.get_patient_attribute_value(@patient, "max_height")
    if (@patient.gender == "F")
      @patient_pregnant = true if @patient.pregnancy_status((session[:datetime] || Time.now())) == "Patient is pregnant"
    end
  end

  def family_history
    patient = Patient.find(params[:patient_id])
    @patient = patient
  end

  def social_history
    @patient = Patient.find(params[:patient_id])
  end

  def general_health
    @patient = Patient.find(params[:patient_id])

    if @patient.get_general_health(session[:datetime])
      @existing_conditions = ["Heart disease", "Stroke", "TIA", "Diabetes", "Kidney Disease"]
      @drugs = MedicationService.hypertension_dm_drugs.collect { |x| x.concept.fullname}
      @drugs = @drugs.sort.uniq
    else
      redirect_to next_task(@patient)
    end
  end

  def medical_history
    @patient = Patient.find(params[:patient_id])
    @prev_risk_factors = @patient.current_risk_factors((session[:datetime].to_date rescue Date.today))
    option_set = ConceptSet.where(["concept_set =?", Concept.find_by_name("HYPERTENSION RISK FACTORS").id]).order("sort_weight")
    @options = option_set.map{|item|next if item.concept.blank? ; [item.concept.fullname, item.concept.fullname] }
    if session[:datetime]
      @retrospective = true
    else
      @retrospective = false
    end
  end
  
  def risk_factors_index 
  	@patient = Patient.find(params[:patient_id])
  	@risk_factors = @patient.current_risk_factors((session[:datetime].to_date rescue Date.today))
  end
  
  def lab_results
  end

  def complications
  end

  def bp_triage
  end

  def update_outcome
  end

  def create
    #raise params["encounter"]["observations"].first.inspect
    encounter = Encounter.new()
    encounter.encounter_type = EncounterType.find_by_name(params["encounter"]["encounter_type_name"]).id
    encounter.patient_id = params['encounter']['patient_id']
    encounter.encounter_datetime = params['encounter']['encounter_datetime']

    if params[:filter] and !params[:filter][:provider].blank?
      user_person_id = User.find_by_username(params[:filter][:provider]).person_id

    else
  
      if !session[:datetime].blank? && !session[:htn_provider_id].blank?
        user_person_id = session[:htn_provider_id]

      else

        user_person_id = User.find_by_user_id(params['encounter']['provider_id']).person_id
      end

    end

    encounter.provider_id = user_person_id
    encounter.creator = current_user.user_id
    encounter.save
    create_obs(encounter, params)
=begin
  if encounter.name == "VITALS" && encounter.observations.length == 2
    bp  = encounter.patient.current_bp(encounter.encounter_datetime)
    if !bp.blank? && ((!bp[0].blank? && bp[0] > 140) || (!bp[1].blank?  && bp[1] > 90))
      redirect_to "/htn_encounter/bp_management?patient_id=#{encounter.patient_id}" and return
    end
  end
=end

    if !params[:state].blank?
      htn_program = Program.find_by_name("HYPERTENSION PROGRAM")
      # get state id
      state = ProgramWorkflowState.where(["program_workflow_id = ? AND concept_id = ?",
          ProgramWorkflow.where(["program_id = ?", htn_program.id]).first.id,
          Concept.find_by_name(params[:state]).id]).first.id
      unless state.blank?
        patient_program = PatientProgram.where(["patient_id = ? AND program_id = ? AND date_enrolled <= ?",
            encounter.patient_id,htn_program.id,params['encounter']['encounter_datetime'].to_date]).first

        state_within_range = PatientState.where(["patient_program_id = ? AND state = ? AND start_date <= ? AND end_date >= ?",
            patient_program.id, state, params['encounter']['encounter_datetime'].to_date,
            params['encounter']['encounter_datetime'].to_date]).first

        if state_within_range.blank?
          last_state = PatientState.where(["patient_program_id = ? AND start_date <= ? ",
              patient_program.id, params['encounter']['encounter_datetime'].to_date]).order("start_date ASC").last
          if ! last_state.blank?
            last_state.end_date = params['encounter']['encounter_datetime'].to_date
            last_state.save
          end

          state_after = PatientState.where(["patient_program_id = ? AND start_date >= ? ",
              patient_program.id, params['encounter']['encounter_datetime'].to_date]).order("start_date ASC").last

          new_state = PatientState.new(:patient_program_id => patient_program.id,
            :start_date => params['encounter']['encounter_datetime'].to_date,
            :state => state )
          new_state.end_date = state_after.start_date if !state_after.blank?
          new_state.save
        end

      end
    end
	
    if !params[:reroute].blank?
      redirect_to "/htn_encounter/bp_management?patient_id=#{Patient.find(params['encounter']['patient_id']).id}" and return
    end

    if !params[:return].blank?
      render plain: true and return
    else
      redirect_to next_task(Patient.find(params['encounter']['patient_id']))
    end
  end

  def create_or_update(params)
    @patient = Patient.find(params['encounter']['patient_id'])
    session_date = params["encounter"]["encounter_datetime"] rescue Date.today
    encounter_type = EncounterType.find_by_name(params["encounter"]["encounter_type_name"]).id
    encounter = @patient.encounters.where(["encounter_type = ? AND DATE(encounter_datetime) = ?",
        encounter_type, session_date]).last
	
    if encounter.blank?
		  encounter = Encounter.create(
			  :encounter_datetime => (session[:datetime].to_datetime rescue DateTime.now),
			  :encounter_type => encounter_type,
			  :creator => current_user.user_id,
			  :provider_id => ((session[:datetime].blank? || session[:htn_provider_id].blank?) ?
            current_user.person_id : session[:htn_provider_id]),
			  :location_id => @current_location.id,
			  :patient_id => @patient.id
		  )
    end
	
    (params['encounter']['observations'] || []).each do |observation|
      concept_id = ConceptName.find_by_name(observation['concept_name']).concept_id
      obs = encounter.observations.where(["concept_id = ? AND voided = 0", concept_id]).last
    end

    Observation.create(
      :obs_datetime => encounter.encounter_datetime,
      :encounter_id => encounter.id,
      :person_id => @patient.id,
      :location_id => @current_location,
      :concept_id => concept_id,
      :creator => current_user.user_id,
      :value_text => notes,
      :value_drug => drug_id
		)     
  end
 
  def create_obs(encounter , params)
    # Observation handling
    # Chunk of code re-used from ccc
    (params[:observations] || []).each do |observation|
      next if observation[:concept_name] == ""
      # Check to see if any values are part of this observation
      # This keeps us from saving empty observations
      values = ['coded_or_text', 'coded_or_text_multiple', 'group_id', 'boolean', 'coded', 'drug', 'datetime', 'numeric', 'modifier', 'text'].map { |value_name|
        observation["value_#{value_name}"] unless observation["value_#{value_name}"].blank? rescue nil
      }.compact

      values = values.flatten.reject { |v| v.empty? }
      next if values.length == 0

      observation[:value_text] = observation[:value_text].join(", ") if observation[:value_text].present? && observation[:value_text].is_a?(Array)
      observation.delete(:value_text) unless observation[:value_coded_or_text].blank?
      observation[:encounter_id] = encounter.id
      observation[:obs_datetime] = encounter.encounter_datetime || Time.now()
      observation[:person_id] ||= encounter.patient_id
      observation[:concept_name].upcase ||= "DIAGNOSIS" if encounter.type.name.upcase == "OUTPATIENT DIAGNOSIS"

      # Handle multiple select

      if observation[:value_coded_or_text_multiple] && observation[:value_coded_or_text_multiple].is_a?(String)
        observation[:value_coded_or_text_multiple] = observation[:value_coded_or_text_multiple].split(';')
      end

      if observation[:value_coded_or_text_multiple] && observation[:value_coded_or_text_multiple].is_a?(Array)
        observation[:value_coded_or_text_multiple].compact!
        observation[:value_coded_or_text_multiple].reject!{|value| value.blank?}
      end

      # convert values from 'mmol/litre' to 'mg/declitre'
      if(observation[:measurement_unit])
        observation[:value_numeric] = observation[:value_numeric].to_f * 18 if ( observation[:measurement_unit] == "mmol/l")
        observation.delete(:measurement_unit)
      end

      if(!observation[:parent_concept_name].blank?)
        concept_id = Concept.find_by_name(observation[:parent_concept_name]).id rescue nil
        observation[:obs_group_id] = Observation.find(:last, :conditions=> ['concept_id = ? AND encounter_id = ?', concept_id, encounter.id], :order => "obs_id ASC, date_created ASC").id rescue ""
        observation.delete(:parent_concept_name)
      else
        observation.delete(:parent_concept_name)
        observation.delete(:obs_group_id)
      end

      extracted_value_numerics = observation[:value_numeric]
      extracted_value_coded_or_text = observation[:value_coded_or_text]

      #TODO : Added this block with Yam, but it needs some testing.
      if params[:location]
        if encounter.encounter_type == EncounterType.find_by_name("ART ADHERENCE").id
          passed_concept_id = Concept.find_by_name(observation[:concept_name]).concept_id rescue -1
          obs_concept_id = Concept.find_by_name("AMOUNT OF DRUG BROUGHT TO CLINIC").concept_id rescue -1
          if observation[:order_id].blank? && passed_concept_id == obs_concept_id
            order_id = Order.joins("INNER JOIN drug_order USING (order_id)").where(["orders.patient_id = ? AND
              drug_order.drug_inventory_id = ? AND orders.start_date < ?", encounter.patient_id,
                observation[:value_drug], encounter.encounter_datetime.to_date]
            ).order("orders.start_date DESC").select("orders.order_id").first.order_id rescue nil
            if !order_id.blank?
              observation[:order_id] = order_id
            end
          end
        end
      end

      if observation[:value_coded_or_text_multiple] && observation[:value_coded_or_text_multiple].is_a?(Array) && !observation[:value_coded_or_text_multiple].blank?
        values = observation.delete(:value_coded_or_text_multiple)
        values.each do |value|
          observation[:value_coded_or_text] = value
          if observation[:concept_name].humanize == "Tests ordered"
            observation[:accession_number] = Observation.new_accession_number
          end

          observation = update_observation_value(observation)

          Observation.create(observation.permit!)
        end
      elsif extracted_value_numerics.class == Array
        extracted_value_numerics.each do |value_numeric|
          observation[:value_numeric] = value_numeric

          if !observation[:value_numeric].blank? && !(Float(observation[:value_numeric]) rescue false)
            observation[:value_text] = observation[:value_numeric]
            observation.delete(:value_numeric)
          end

          Observation.create(observation.permit!)
        end
      else
        observation.delete(:value_coded_or_text_multiple)
        observation = update_observation_value(observation) if !observation[:value_coded_or_text].blank?

        if !observation[:value_numeric].blank? && !(Float(observation[:value_numeric]) rescue false)
          observation[:value_text] = observation[:value_numeric]
          observation.delete(:value_numeric)
        end

        Observation.create(observation.permit!)
      end
    end
  end

  def update_observation_value(observation)
    # Chunk of code re-used from ccc
    value = observation[:value_coded_or_text]
    value_coded_name = ConceptName.find_by_name(value)

    if value_coded_name.blank?
      observation[:value_text] = value
    else
      observation[:value_coded_name_id] = value_coded_name.concept_name_id
      observation[:value_coded] = value_coded_name.concept_id
    end
    observation.delete(:value_coded_or_text)
    return observation
  end

  def assessment

    @patient = Patient.find(params[:patient_id]) rescue nil

    @diabetic = ConceptName.find_by_concept_id(PatientService.get_patient_attribute_value(@patient, "Patient has Diabetes")).name rescue ""

    @status = Observation.find_by_sql("SELECT * from obs
          WHERE concept_id = (SELECT concept_id FROM concept_name WHERE name = 'current smoker' LIMIT 1)
          AND voided = 0
          AND person_id = #{@patient.id} ORDER BY obs_datetime DESC LIMIT 1").first.value_coded rescue "No"

    #raise @status.to_yaml
    @smoking_status = ConceptName.find_by_concept_id(@status).name rescue "No"

    @systolic_value = Observation.find_by_sql("SELECT * from obs
          WHERE concept_id = (SELECT concept_id FROM concept_name WHERE name = 'systolic blood pressure' LIMIT 1)
          AND voided = 0
          AND person_id = #{@patient.id} ORDER BY obs_datetime DESC LIMIT 1").first.value_numeric rescue 0

    cholesterol_value = Observation.find_by_sql("SELECT * from obs
          WHERE concept_id = (SELECT concept_id FROM concept_name WHERE name = 'cholesterol test type' LIMIT 1)
          AND voided = 0
          AND person_id = #{@patient.id} ORDER BY obs_datetime DESC LIMIT 1").first.obs_id rescue nil

    @cholesterol_value = Observation.where(['obs_group_id = ?', cholesterol_value]).first.value_numeric.to_i rescue 0

    @first_visit = false #is_first_hypertension_clinic_visit(@patient.id)
  end

  def bp_management
    @patient = Patient.find(params[:patient_id])

    if !@patient.were_htn_risk_factors_captured?((session[:datetime] || Date.today))
      redirect_to "/htn_encounter/medical_history?patient_id=#{@patient.id}" and return
    elsif  params[:skip_provider_check].blank? && !session[:datetime].blank?
      redirect_to "/htn_encounter/update_htn_provider?patient_id=#{@patient.id}" and return
    end

    if session[:datetime].blank? && !session[:htn_provider_id]
      session.delete(:htn_provider_id)
    end
  
    date = session[:datetime].to_date rescue Date.today
    @patient_program = @patient.enrolled_on_program(Program.find_by_name("Hypertension program").id,date, true)
    @bp_trail =  @patient.bp_management_trail(date)
    @normatensive = @patient.normatensive(@bp_trail)
    @note = @patient.pregnancy_status(date) if @patient.gender == "F"
    @risks = @patient.current_risk_factors(date).length

    @hypertension_obs = Observation.where(["person_id =? AND concept_id =?", params[:patient_id],
        Concept.find_by_name("PATIENT HAS HYPERTENSION").concept_id]).last

    @patient_on_bp_drugs = false
    treatment_status_concept_id = Concept.find_by_name("TREATMENT STATUS").id
    treatment_status = Observation.where(["person_id =? AND concept_id =? AND value_text REGEXP ?",
        params[:patient_id], treatment_status_concept_id, "BP Drugs started"]).last
    unless treatment_status.blank?
      @patient_on_bp_drugs = true
    end

    @bp_drug_use_history = Observation.where(["person_id =? AND concept_id =?", params[:patient_id],
        Concept.find_by_name('DRUG USE HISTORY').id]).last

    @first_visit = false
    transfer_obs =  Observation.where(["person_id =? AND concept_id =?", params[:patient_id],
        Concept.find_by_name('TRANSFERRED').id]).last
    @first_visit = true if transfer_obs.blank?
    current_bp_drugs = @patient.current_bp_drugs
    @first_visit = false unless current_bp_drugs.blank?
  end
 
  def update_htn_provider
    @patient = Patient.find(params[:patient_id])

    if !params[:update_htn_provider].blank?
      session_provider = User.find_by_username(params[:filter][:provider]) rescue nil
      session[:htn_provider_id] = session_provider.person_id if !session_provider.blank?
      redirect_to "/htn_encounter/bp_management?patient_id=#{@patient.id}&skip_provider_check=true"
    end
  end

  def bp_drug_management
    @patient = Patient.find(params[:patient_id])
    session_date = session[:datetime].to_date rescue Date.today
    @current_drugs = {}
    @patient.current_bp_drugs(session_date).each {|drg|
      @current_drugs[drg] = true
    }
   
    dispensed_concept_id = Concept.find_by_name("AMOUNT DISPENSED").concept_id rescue -1
    @last_dispensation = {}
    (@current_drugs || []).each do |drug_name, value|
    	next if value != true
    	drug = Drug.find_by_name(drug_name)
      last_dispensation = Encounter.find_by_sql([
          "SELECT SUM(obs.value_numeric) AS value_numeric, MAX(obs_datetime) AS obs_datetime, 0 AS remaining FROM encounter INNER JOIN obs ON obs.encounter_id = encounter.encounter_id AND encounter.voided = 0
				WHERE obs.value_drug = ? AND encounter.encounter_type = ? AND 
				encounter.patient_id = ? AND DATE(encounter.encounter_datetime) < ?
				AND obs.concept_id = ? GROUP BY DATE(obs_datetime) ORDER BY obs.obs_datetime DESC LIMIT 1", 
          drug.id, EncounterType.find_by_name("DISPENSING").id, @patient.id, session_date, dispensed_concept_id]).last rescue nil

      remaining_last_time = Observation.where(["concept_id = ? AND person_id = ? AND value_drug = ? AND 
          DATE(obs_datetime) = ?", ConceptName.find_by_name("Amount of drug remaining at home").concept_id,
          @patient.id,drug.id,last_dispensation.obs_datetime.to_date]).last.value_numeric rescue 0

      last_dispensation.remaining = ((last_dispensation.value_numeric.to_i + remaining_last_time.to_i) - (session_date -
            last_dispensation.obs_datetime.to_date).to_i) rescue nil # == days for a pill per day
		 
      @last_dispensation[drug_name] = last_dispensation if !last_dispensation.blank?
    end
  end

  def update_remaining_drugs
    @patient = Patient.find(params[:patient_id])
    session_date = (session[:datetime].to_date rescue Date.today)

    encounter_type = EncounterType.find_by_name("HYPERTENSION MANAGEMENT").id
    encounter = @patient.encounters.where(["encounter_type = ? AND DATE(encounter_datetime) = ?",
        encounter_type, (session[:datetime].to_date rescue Date.today)]).last

    if !params[:pills].blank?
      if encounter.blank?
        encounter = Encounter.create(
          :encounter_datetime => (session[:datetime].to_datetime rescue DateTime.now),
          :encounter_type => encounter_type,
          :creator => current_user.user_id,
          :provider_id =>  ((session[:datetime].blank? || session[:htn_provider_id].blank?) ?
              current_user.person_id : session[:htn_provider_id]),
          :location_id => @current_location.id,
          :patient_id => @patient.id
        )
      end
    
      drug_id = Drug.find_by_name(params[:drug_name]).id

      order_id = Order.joins("INNER JOIN drug_order USING (order_id)").where(["orders.patient_id = ? AND
        drug_order.drug_inventory_id = ? AND orders.start_date < ?",
          encounter.patient_id, drug_id, encounter.encounter_datetime.to_date]
      ).select("orders.order_id").order("orders.start_date DESC").first.order_id rescue nil


      concept_id = ConceptName.find_by_name("Amount of drug remaining at home").concept_id

      drug_id = Drug.find_by_name(params[:drug_name]).id

      obs = Observation.where(["person_id = ? AND concept_id = ? AND encounter_id = ? AND value_drug = ?",
          @patient.id, concept_id, encounter.id, drug_id]).last
      if obs.blank?
        obs = Observation.create(
          :obs_datetime => encounter.encounter_datetime,
          :encounter_id => encounter.id,
          :person_id => @patient.id,
          :location_id => @current_location,
          :concept_id => concept_id,
          :order_id => order_id,
          :creator => current_user.user_id,
          :value_numeric => params[:pills],
          :value_drug => drug_id
        )
      else
        obs.update_attributes(:value_numeric => params[:pills])
      end
    
      dispensed_concept_id = Concept.find_by_name("AMOUNT DISPENSED").concept_id rescue -1
      adherence_concept_id = Concept.find_by_name('WHAT WAS THE PATIENTS ADHERENCE FOR THIS DRUG ORDER').concept_id rescue -1
    
      last_dispensation = Encounter.find_by_sql([
          "SELECT SUM(obs.value_numeric) AS value_numeric, MAX(obs_datetime) AS obs_datetime FROM encounter INNER JOIN obs ON obs.encounter_id = encounter.encounter_id AND encounter.voided = 0
    		WHERE obs.value_drug = ? AND encounter.encounter_type = ? AND encounter.patient_id = ?
    			AND DATE(encounter.encounter_datetime) < ? AND obs.concept_id = ? 
    		GROUP BY DATE(obs_datetime) ORDER BY obs.obs_datetime DESC LIMIT 1", drug_id,
          EncounterType.find_by_name("DISPENSING").id, @patient.id, session_date, dispensed_concept_id
        ]).last rescue nil

      remaining_last_time = Observation.where(["concept_id = ? AND person_id = ? AND value_drug = ? AND 
          DATE(obs_datetime) = ?", ConceptName.find_by_name("Amount of drug remaining at home").concept_id,
          @patient.id,drug_id,last_dispensation.obs_datetime.to_date]).last.value_numeric rescue 0

      adherence = nil
      expected_amount_remaining = nil
      if !last_dispensation.blank?
        amount_given_last_time = last_dispensation.value_numeric.to_i
        expected_amount_remaining =  (amount_given_last_time + remaining_last_time.to_i) - (session_date -
            last_dispensation.obs_datetime.to_date).to_i # == days for a pill per day
        amount_remaining = params[:pills].to_i
        adherence = (100*(amount_given_last_time - amount_remaining) / (amount_given_last_time - expected_amount_remaining)).round
      end
=begin
    adherence = ActiveRecord::Base.connection.select_value(              
      "SELECT adherence_cal(#{@patient.id}, #{drug_id}, '#{encounter.encounter_datetime.to_date}')"
    ).to_i rescue 0
        
    adherence_to_show = 0
    adherence_over_100 = 0
    adherence_below_100 = 0
    over_100_done = false
    below_100_done = false

    drug_adherence = adherence
    if drug_adherence <= 100
      adherence_below_100 = adherence.to_i if adherence_below_100 == 0
      adherence_below_100 = adherence.to_i if drug_adherence <= adherence_below_100
      below_100_done = true
    else  
      adherence_over_100 = adherence.to_i if adherence_over_100 == 0
      adherence_over_100 = adherence.to_i if drug_adherence >= adherence_over_100
      over_100_done = true
    end  
      
    over_100 = 0
    below_100 = 0
    over_100 = adherence_over_100 - 100 if over_100_done
    below_100 = 100 - adherence_below_100 if below_100_done

    if over_100 >= below_100 and over_100_done
      adherence = 100 - (adherence_over_100 - 100)
    else
      adherence = adherence_below_100
    end        
=end

      obs = Observation.where(["person_id = ? AND concept_id = ? AND encounter_id = ? AND
          value_drug = ? AND DATE(obs_datetime) =?", @patient.id, adherence_concept_id,
          encounter.id, drug_id, session_date]).last
      if !adherence.blank?
        if obs.blank?
          obs = Observation.create(
            :obs_datetime => encounter.encounter_datetime,
            :encounter_id => encounter.id,
            :person_id => @patient.id,
            :location_id => @current_location,
            :concept_id => adherence_concept_id,
            :order_id => order_id,
            :creator => current_user.user_id,
            :value_numeric => adherence,
            :value_modifier => '%',
            :value_text => '',
            :value_drug => drug_id
          )
        else
          obs.update_attributes(:value_numeric => adherence)
        end
      end
      render :text => [adherence, expected_amount_remaining].to_json
    else
      #return a no template error
    end
  end

  def change_drugs
    @patient = Patient.find(params[:patient_id])
    session_date = session[:datetime].to_date rescue Date.today
    @current_drugs = {}
    @patient.current_bp_drugs(session_date).each {|drg|
      @current_drugs[drg] = true
    }   
    @notes = @patient.drug_notes(session_date)
  end

  def save_notes
    @patient = Patient.find(params[:patient_id])
    drug_name = params[:drug_name]
    drug = Drug.find_by_name(drug_name) rescue nil
    notes = params[:notes]
    session_date = session[:datetime].to_date rescue Date.today     

    if !drug.blank?
	
      encounter_type = EncounterType.find_by_name("HYPERTENSION MANAGEMENT").id
      encounter = @patient.encounters.where(["encounter_type = ? AND DATE(encounter_datetime) = ?",
          encounter_type, session_date]).last
	
      if encounter.blank?
        encounter = Encounter.create(
          :encounter_datetime => (session[:datetime].to_datetime rescue DateTime.now),
          :encounter_type => encounter_type,
          :creator => current_user.user_id,
          :provider_id => ((session[:datetime].blank? || session[:htn_provider_id].blank?) ?
              current_user.person_id : session[:htn_provider_id]),
          :location_id => @current_location.id,
          :patient_id => @patient.id
        )
      end


      concept_id = ConceptName.find_by_name("Notes").concept_id

      drug_id = drug.id

      Observation.create(
        :obs_datetime => encounter.encounter_datetime,
        :encounter_id => encounter.id,
        :person_id => @patient.id,
        :location_id => @current_location,
        :concept_id => concept_id,
        :creator => current_user.user_id,
        :value_text => notes,
        :value_drug => drug_id
      )
		
		
    else
    	
    end
    render :text => "ok"
  end

  def refer_to_clinician
    refer_concept = Concept.find_by_name("REFER PATIENT TO CLINICIAN")
    yes_concept = ConceptName.find_by_name("YES")
    obs = Observation.where([" person_id = ? AND obs_datetime BETWEEN ? AND ? AND concept_id = ?",
        params[:patient_id], params[:date].to_date.strftime('%Y-%m-%d 00:00:00'),
        params[:date].to_date.strftime('%Y-%m-%d 23:59:59'), refer_concept.id]).last
    if obs.blank?
      obs = Observation.new()
      obs.encounter_id = Encounter.where(["patient_id = ? AND encounter_datetime BETWEEN ? AND ? AND encounter_type = ?",
          params[:patient_id],params[:date].to_date.strftime('%Y-%m-%d 00:00:00'),
          params[:date].to_date.strftime('%Y-%m-%d 23:59:59'),
          EncounterType.find_by_name("Vitals").id]).first.id
      obs.person_id = params[:patient_id]
      obs.concept_id = refer_concept.id
      obs.obs_datetime = params[:date].to_date.strftime('%Y-%m-%d 00:00:00')
      obs.creator = current_user.user_id
    end
    obs.value_coded = yes_concept.concept_id
    obs.value_coded_name_id = yes_concept.concept_name_id
    obs.save
    redirect_to "/patients/show/#{params[:patient_id]}"
  end

  def voluntary_check
    @patient = Patient.find(params[:id])
  end

  def diabetes_initial_visit
    if session[:datetime]
      @retrospective = true
    else
      @retrospective = false
    end
    @patient = Patient.find(params['patient_id'])
  end

  def capture_bp_drugs
    @patient = Patient.find(params['patient_id'])
    if request.method == :post
      drugs = params[:drugs].split(', ')
      vitals_encounter = @patient.encounters.where(["DATE(encounter_datetime) =?
          AND encounter_type =?", Date.today, EncounterType.find_by_name('VITALS').id]).last
      unless vitals_encounter.blank?
        vitals_encounter.observations.create({
            :person_id => params['patient_id'],
            :concept_id => Concept.find_by_name('DRUG USE HISTORY').id,
            :value_text => drugs.join(', '),
            :obs_datetime => Time.now
          })
      end
      redirect_to :controller => "htn_encounter", :action => "bp_management", :patient_id => params[:patient_id] and return
    end
  end
  
  def redirect_to_next_task
    redirect_to next_task(Patient.find(params['patient_id']))
  end

  def create_vitals_transfer_obs

    todays_date = (session[:datetime] || Date.today)
    patient = Patient.find(params[:patient_id])
    task = main_next_task(Location.current_location, patient,todays_date)
    todays_patient_vitals_enc = patient.encounters.where(["encounter_type =? AND DATE(encounter_datetime) =? AND
      voided=0", EncounterType.find_by_name("VITALS").id, todays_date]).last
=begin
    if todays_patient_vitals_enc.blank?
      todays_patient_vitals_enc = patient.encounters.create(
        :encounter_type => EncounterType.find_by_name("VITALS").id,
        :encounter_datetime => todays_date
      )
    end
=end
    todays_patient_vitals_enc.observations.create(
      :person_id => params[:patient_id],
      :concept_id => Concept.find_by_name('TRANSFERRED').id,
      :obs_datetime => Time.now,
      :value_coded => Concept.find_by_name("#{params[:value]}").id
    )

    #sbp_threshold = CoreService.get_global_property_value("htn_systolic_threshold").to_i
    #dbp_threshold = CoreService.get_global_property_value("htn_diastolic_threshold").to_i
    #bp = patient.current_bp(todays_date)
    
    next_url = task.url
    if (params[:value].match(/YES/i))
      #if ((!bp[0].blank? && bp[0] > sbp_threshold) || (!bp[1].blank?  && bp[1] > dbp_threshold))
      next_url = "/htn_encounter/diabetes_initial_visit?patient_id=#{patient.id}"
      #end
    end
 
    render :text => next_url and return
  end

  def hypertension_diagnosis
    @patient = Patient.find(params[:patient_id])
    todays_date = (session[:datetime] || Date.today)
    
    if request.post?
      #HYPERTENSION DIAGNOSIS DATE
      #PATIENT HAS HYPERTENSION
      diagnosis_date = params[:diagnosis_date].to_date rescue nil
      hiv_clinic_consultation_enc_type_id = EncounterType.find_by_name("HIV CLINIC CONSULTATION").encounter_type_id
      hiv_clinic_consultation_enc =  @patient.encounters.where(["encounter_type =? AND DATE(encounter_datetime) =?",
          hiv_clinic_consultation_enc_type_id, todays_date.to_date]).last

      hiv_clinic_consultation_enc.observations.create({
          :person_id => params[:patient_id],
          :concept_id => Concept.find_by_name("PATIENT HAS HYPERTENSION").concept_id,
          :value_coded => Concept.find_by_name(params[:diagnosis_status]).concept_id,
          :obs_datetime => todays_date
        })

      hiv_clinic_consultation_enc.observations.create({
          :person_id => params[:patient_id],
          :concept_id => Concept.find_by_name("HYPERTENSION DIAGNOSIS DATE").concept_id,
          :value_datetime => params[:diagnosis_date].to_date,
          :obs_datetime => todays_date
        }) unless diagnosis_date.blank?

      redirect_to("/htn_encounter/bp_management?patient_id=#{params[:patient_id]}")
    end


  end

end
