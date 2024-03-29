class GenericRegimensController < ApplicationController

	def new

		if session[:datetime]
			@retrospective = true
		else
			@retrospective = false
		end
		@patient = Patient.find(params[:patient_id] || session[:patient_id]) rescue nil
		@patient_bean = PatientService.get_patient(@patient.person)
    @gender = @patient.person.gender.upcase
		@programs = @patient.patient_programs.all

		allergic_to_sulphur_session_date = session[:datetime].to_date rescue Date.today
    ################################################ check if on TB treatment ##########################
    on_tb_treatment = Observation.where(["person_id = ? AND concept_id = ?
      AND obs_datetime <= ?", @patient.patient_id, ConceptName.find_by_name('TB treatment').concept_id,
																				 allergic_to_sulphur_session_date.strftime('%Y-%m-%d 23:59:59')]).order("obs_datetime DESC").first.to_s #rescue ''
    
    if on_tb_treatment.match(/Yes/i)
      @on_tb_treatment = true 
    else
      @on_tb_treatment = false
    end
    ##########################################################################################################


		@allergic_to_sulphur = Patient.allergic_to_sulpher(@patient, allergic_to_sulphur_session_date) #chunked

    ########################### if patient is being initiated/re started and if given regimen that contains NVP ##########
    @patient_initiated =  PatientService.patient_initiated(@patient.patient_id, allergic_to_sulphur_session_date)
    ################################################################################################################

    ################################################################################################################
    @prescribe_arvs_set = prescribe_medication_set(@patient, allergic_to_sulphur_session_date, 'ARVS')
    if @allergic_to_sulphur == 'Yes'
      @prescribe_medication_set = false
    else
      @prescribe_cpt_set = prescribe_medication_set(@patient, allergic_to_sulphur_session_date, 'CPT')
    end
    @prescribe_ipt_set = prescribe_medication_set(@patient, allergic_to_sulphur_session_date, 'Isoniazid')
    @custom_regimen_options = custom_regimen_options(@patient)
    ################################################################################################################

		@current_regimen = current_regimen(@patient.id) rescue nil
    @current_regimen_text = "Current Regimen: <b>#{@current_regimen}</b> " unless @current_regimen.blank?

    @current_regimen_index = @current_regimen.to_i unless @current_regimen.blank?
		#@hiv_programs = @patient.patient_programs.not_completed.in_programs('HIV PROGRAM')
    @hiv_programs = []
    @programs.each do |prog|
      if prog.program.name.upcase == "HIV PROGRAM"
        @hiv_programs << prog #unless ProgramWorkflowState.find_state(prog.patient_states.last.state).concept.fullname.match(/treatment stopped/i)
      end
    end

		@reason_for_art_eligibility = PatientService.reason_for_art_eligibility(@patient)
		@current_weight = PatientService.get_patient_attribute_value(@patient, "current_weight")

		@tb_encounter = Patient.tb_encounter(@patient)  #chunked

		@tb_programs = @patient.patient_programs.in_uncompleted_programs(['TB PROGRAM', 'MDR-TB PROGRAM'])

		@current_regimens_for_programs = current_regimens_for_programs
    @regimen_formulations = []
		@tb_regimen_formulations = []

    (@current_regimens_for_programs || {}).each do |patient_program_id , regimen_id|
      @regimen_formulations = formulation(@patient,regimen_id) if PatientProgram.find(patient_program_id).program.name.match(/HIV PROGRAM/i)
			@hiv_regimen_map = regimen_id if PatientProgram.find(patient_program_id).program.name.match(/HIV PROGRAM/i)
      @drug_stock = drug_stock(@patient, regimen_id) if PatientProgram.find(patient_program_id).program.name.match(/HIV PROGRAM/i)
			@tb_regimen_formulations = formulation(@patient,regimen_id) if PatientProgram.find(patient_program_id).program.name.match(/TB PROGRAM/i)
    end
		@current_regimen_names_for_programs = current_regimen_names_for_programs

		@current_hiv_program_state = Patient.current_hiv_program_state(@patient) #chunked

		session_date = session[:datetime].to_date rescue Date.today
    @session_date = session_date
    
		pre_hiv_clinic_consultation = Patient.hiv_encounter(@patient, 'PART_FOLLOWUP', session_date)# chunked
		hiv_clinic_consultation = Patient.hiv_encounter(@patient, 'HIV CLINIC CONSULTATION', session_date)# chunked
    @date_of_first_hiv_clinic_enc = Patient.date_of_first_hiv_clinic_enc(@patient, session_date)

		@hiv_clinic_consultation = false

		if ((not pre_hiv_clinic_consultation.blank?) or (not hiv_clinic_consultation.blank?))
			@hiv_clinic_consultation = true
		end

		tb_visit_obs = Encounter.where(
      ["DATE(encounter_datetime) = ? AND patient_id = ? AND encounter_type = ?",
        session_date.to_date, @patient.id, EncounterType.find_by_name("TB VISIT").id],
			).includes(:observations).order("encounter_datetime DESC,date_created DESC")

		prescribe_tb_medication = false
		@transfer_out_patient = false;
		(tb_visit_obs || []).each do | obs |
			(obs.observations.each || []).each do |observation|
        if observation.concept_id == (Concept.find_by_name('Prescribe drugs').concept_id rescue nil)
          prescribe_tb_medication = true if Concept.find(observation.value_coded).fullname.upcase == 'YES'
        end

        if observation.concept_id == (Concept.find_by_name('Continue treatment').concept_id rescue nil)
          @transfer_out_patient = true if Concept.find(observation.value_coded).fullname.upcase == 'NO'
        end
      end
		end

		treatment_obs = Patient.hiv_encounter(@patient, 'TREATMENT', session_date)# chunked
		tb_medication_prescribed = false
		arvs_prescribed = false

		(treatment_obs || []).each do | obs |
			(obs.observations.each || []).each do |observation|
        if observation.concept_id == (Concept.find_by_name('TB regimen type').concept_id rescue nil)
          tb_medication_prescribed = true
        end

        if observation.concept_id == (Concept.find_by_name('ARV regimen type').concept_id rescue nil)
          arvs_prescribed = true
        end
      end
		end


		@prescribe_tb_drugs = false
		if (not @tb_programs.blank?) and prescribe_tb_medication and !tb_medication_prescribed
			@prescribe_tb_drugs = true
		end

		sulphur_allergy_obs = Patient.obs_available_in(@patient, ["HIV CLINIC CONSULTATION", "TB VISIT"],  session_date) #chunked

		hiv_clinic_consultation_obs = Patient.obs_available_in(@patient, ["HIV CLINIC CONSULTATION"],  session_date) #chunked
    hiv_symptoms_ids = Patient.concept_set("COMMON MALAWI ART SYMPTOM SET")#chunked
    hiv_additional_symptoms_ids = Patient.concept_set("ADDITIONAL MALAWI ART SYMPTOM SET")#chunked

		hiv_symptoms_ids += hiv_additional_symptoms_ids

    #side_effects_concept_id = Concept.find_by_name("MALAWI ART SIDE EFFECTS").concept_id
    #symptom_present_conept_id = Concept.find_by_name("SYMPTOM PRESENT").concept_id

    #side_effects_contraindications = @patient.person.observations.find(:all, :conditions => ["concept_id IN (?) AND
    #DATE(obs_datetime) <= ?", [side_effects_concept_id, symptom_present_conept_id], session_date])

    side_effects_contraindications = Patient.side_effects_obs_ever(@patient, session_date)
    
    @side_effects_answers = Patient.todays_side_effects(@patient, session_date)
    contraindication_date = Patient.date_of_first_hiv_clinic_enc(@patient, session_date)

    @side_effects_contraindications = {}
    (side_effects_contraindications || []).each do |obs|
      date = obs.obs_datetime.to_date.strftime("%d/%b/%Y")
      @side_effects_contraindications[date] = {} if @side_effects_contraindications[date].blank?
      if date.to_date <= contraindication_date.to_date
        type = 'contraindication'
      else
        type = 'side effect'
      end
      @side_effects_contraindications[date][type] = [] if @side_effects_contraindications[date][type].blank?
      @side_effects_contraindications[date][type] << obs.answer_string.squish
    end

		@found_symptoms = []

		@prescribe_art_drugs = false
		(hiv_clinic_consultation_obs || []).each do | obs |
			if obs.concept_id == (Concept.find_by_name('Prescribe drugs').concept_id rescue nil)
				@prescribe_art_drugs = true if Concept.find(obs.value_coded).fullname.upcase == 'YES' and !arvs_prescribed
			end
			if hiv_symptoms_ids.include?(obs.value_coded) and !@found_symptoms.include?(Concept.find(obs.value_coded).fullname.upcase.to_s)
        @found_symptoms += [Concept.find(obs.value_coded).fullname.upcase.to_s]
			end
		end

		@adverse_events = regimen_options
		@regimen_index = Patient.regimen_index(@hiv_regimen_map)

	  session_date = session[:datetime].to_date rescue Date.today
    current_encounters = @patient.encounters.find_by_date(session_date)
    @family_planning_methods = []
    @is_patient_pregnant_value = 'Unknown'

    #................................................................................................................
    if @patient_bean.sex == 'Female'
      for encounter in current_encounters.reverse do

        if encounter.name.humanize.include?('Hiv staging') || encounter.name.humanize.include?('Tb visit') || encounter.name.humanize.include?('Hiv clinic consultation')

          encounter = Encounter.find(encounter.id)

          for obs in encounter.observations do

            if obs.concept_id == ConceptName.find_by_name("IS PATIENT PREGNANT?").concept_id
              @is_patient_pregnant_value = "#{obs.to_s(["short", "order"]).to_s.split(":")[1]}"
            elsif obs.concept_id == ConceptName.find_by_name("CURRENTLY USING FAMILY PLANNING METHOD").concept_id
              @currently_using_family_planning_methods = "#{obs.to_s(["short", "order"]).to_s.split(":")[1]}".squish
            elsif obs.concept_id == ConceptName.find_by_name("FAMILY PLANNING METHOD").concept_id
              @family_planning_methods << "#{obs.to_s(["short", "order"]).to_s.split(":")[1]}".squish.humanize
            end

          end
        end
      end

    end    
    #................................................................................................................
    @vl_result_hash = Patient.vl_result_hash(@patient) rescue nil
    @cpt_drug_stock = cpt_drug_stock
    @fast_track_patient = fast_track_patient?(@patient, session_date)
    @latest_vl_result = Lab.latest_viral_load_result(@patient)
    @patient_on_tb_treatment = patient_on_tb_treatment?(@patient, session_date)
    @patient_tb_suspected = tb_suspected_today?(@patient, session_date)
    @patient_tb_confirmed = tb_confirmed_today?(@patient, session_date)
    @new_guide_lines_start_date = GlobalProperty.find_by_property('new.art.start.date').property_value.to_date rescue session_date
    @history_of_side_effects = Patient.history_of_side_effects(@patient, session_date)
    @today = session_date.to_date.strftime("%d/%b/%Y")

    if @allergic_to_sulphur == 'Yes'
      @prescribe_medication_set = false
    else
      @prescribe_cpt_set = prescribe_medication_set(@patient, session_date, 'CPT')
    end

    @prescribe_ipt_set = prescribe_medication_set(@patient, session_date, 'Isoniazid')
    fast_track_obs_date = fast_track_obs_date(@patient, session_date)

    if @fast_track_patient
      unless fast_track_obs_date.blank?
        if (fast_track_obs_date < session_date)
          #Ignore this logic if Fast Track has been enrolled today
          if (Patient.cpt_prescribed_in_the_last_prescription?(@patient, session_date))
            @prescribe_cpt_set = true
          end

          if (Patient.ipt_prescribed_in_the_last_prescription?(@patient, session_date))
            @prescribe_ipt_set = true
          end
        end
      end
    end

    @cpt_dose = ""
    @ipt_dose = ""
    if @prescribe_cpt_set == true
      dose = MedicationService.other_medications('Cotrimoxazole', @current_weight)
      @cpt_dose = (dose.first rescue '') unless dose.blank?
    end

    if @prescribe_ipt_set == true
      dose = MedicationService.other_medications('Isoniazid', @current_weight)
      @ipt_dose = (dose.first rescue '') unless dose.blank?
    end

	end

  def check_current_regimen_index
		session_date = session[:datetime].to_date rescue Date.today
		patient_program = PatientProgram.find(params[:id])
		options = []
		current_weight = PatientService.get_patient_attribute_value(patient_program.patient, "current_weight", session_date)
		options = MedicationService.regimen_options(current_weight, patient_program.program)
		render plain: (options.to_json)
	end

	def regimen_options
    adverse_options = {
      '0' => { 'adverse' => [
          ['Fever', 'Body pains', 'Vomiting', 'Cough', 'Fever', 'Body pains', 'Vomiting', 'Cough'],
          ['Hepatitis, Skin rash', 'Hepatitis, Skin rash'],
          ['Lipodystrophy, Lactic acidocis', 'Lipodystrophy, Lactic acidocis'],
          ['Treatment failure','Treatment failure']
        ],
				'contraindications' => [
          ['ABC hypersensitivity', 'ABC hypersensitivity'],
					['Hepatitis/Jaundice','Hepatitis/Jaundice']
				],
				'alt1' => [
          ['Fever', 'Body pains', 'Vomiting', 'Cough', '2'],
          ['Hepatitis, Skin rash','ABC/3TC+EFV'],
          ['Lipodystrophy, Lactic acidocis','5'],
          ['Treatment failure','7']
				],
				'alt2'=> [
          ['Fever', 'Body pains', 'Vomiting', 'Cough', '6 or 5 or NS'],
          ['Hepatitis, Skin rash','5 or 4'],
          ['Lipodystrophy, Lactic acidocis','6 or NS'],
          ['Treatment failure','8']
				]
			},
      '1' => { 'adverse' => [
          ['Neuropathy','Neuropathy'],
          ['Hepatitis, Skin rash','Hepatitis, Skin rash'],
          ['Lipodystrophy, Lactic acidocis','Lipodystrophy, Lactic acidocis'],
          ['Treatment failure','Treatment failure']
        ],
				'contraindications' => [
					['Hepatitis/Jaundice','Hepatitis/Jaundice']
				],
				'alt1' => [
          ['Neuropathy','2 or 5'],
          ['Hepatitis, Skin rash','5 or 4'],
          ['Lipodystrophy, Lactic acidocis','5'],
          ['Treatment failure','7']
				],
				'alt2'=> [
          ['Neuropathy','0 or 6'],
          ['Hepatitis, Skin rash',' NS'],
          ['Lipodystrophy, Lactic acidocis','NS'],
          ['Treatment failure','9']
				]
			},
			'2' => { 'adverse' =>[
          ['Hepatitis, Skin rash','Hepatitis, Skin rash'],
          ['Treatment failure','Treatment failure'],
          ['Lipodystrophy, Lactic acidocis','Lipodystrophy, Lactic acidocis'],
          ['Anemia','Anemia']
        ],
				'contraindications' => [
					['Hepatitis/Jaundice','Hepatitis/Jaundice'],
					['Anemia <8g/dl','Anemia <8g/dl']
				],
				'alt1' => [
          ['Hepatitis, Skin rash','4'],
          ['Treatment failure','7'],
          ['Lipodystrophy, Lactic acidocis','5'],
          ['Anemia','0 or 5']
				],
				'alt2'=> [
          ['Hepatitis, Skin rash','5 or 3'],
          ['Treatment failure','9'],
          ['Lipodystrophy, Lactic acidocis','NS'],
          ['Anemia','6']
				]},
			'3' => { 'adverse' =>[
          ['Neuropathy','Neuropathy'],
          ['Hepatitis, Skin rash, psychiat disorder','Hepatitis, Skin rash, psychiat disorder'],
          ['Lipodystrophy, Lactic acidocis','Lipodystrophy, Lactic acidocis'],
          ['Treatment failure','Treatment failure']
        ],
				'contraindications' => [
					['History of psychosis','History of psychosis']
				],
				'alt1' => [
          ['Neuropathy','5'],
          ['Hepatitis, Skin rash, psychiat disorder','0 or 6'],
          ['Lipodystrophy, Lactic acidocis','5'],
          ['Treatment failure','7 or 9']
				],
				'alt2'=> [
          ['Neuropathy','4 or NS'],
          ['Hepatitis, Skin rash, psychiat disorder','NS'],
          ['Lipodystrophy, Lactic acidocis','6'],
          ['Treatment failure','None']
				]},
			'4' => { 'adverse' => [
          ['Anemia','Anemia'],
          ['Lipodystrophy, Lactic acidocis','Lipodystrophy, Lactic acidocis'],
          ['Hepatitis, Skin rash, psychiat disorder','Hepatitis, Skin rash, psychiat disorder'],
          ['Treatment failure','Treatment failure']
        ],
				'contraindications' => [
					['History of psychosis','History of psychosis'],
					['Anaemia <8g/dl','Anaemia <8g/dl']
				],
				'alt1' => [
          ['Anemia','5 or 0'],
          ['Lipodystrophy, Lactic acidocis','5'],
          ['Hepatitis, Skin rash, psychiat disorder','2 or 0'],
          ['Treatment failure','7']
				],
				'alt2'=> [
          ['Anemia','3 or 6'],
          ['Lipodystrophy, Lactic acidocis', 'None'],
          ['Hepatitis, Skin rash, psychiat disorder','6'],
          ['Treatment failure','9']
				]},
			'5' => { 'adverse' =>[
          ['Kidney Failure','Kidney Failure'],
          ['Hepatitis, Skin rash, psychosis','Hepatitis, Skin rash, psychosis'],
          ['Persistent dizziness, Visual disturbances', 'Persistent dizziness, Visual disturbances'],
          ['Treatment failure','Treatment failure']
				],
				'contraindications' => [
					['History of psychosis','History of psychosis'],
					['Renal failure','Renal failure']
				],
				'alt1' => [
          ['Kidney Failure','0'],
          ['Hepatitis, Skin rash, psychosis','6'],
          ['Persistent dizziness, Visual disturbances', '6'],
          ['Treatment failure','8']
				],
				'alt2'=> [
          ['Renal Failure','2'],
          ['Hepatitis, Skin rash, psychosis','0 or 2'],
          ['Persistent dizziness, Visual disturbances', '0 or 2'],
          ['Treatment failure','NS']
				]},
			'6' => { 'adverse' =>[
          ['Kidney failure','Kidney failure'],
          ['Hepatitis, Skin rash','Hepatitis, Skin rash'],
          ['Treatment failure','Treatment failure']
				],
				'contraindications' => [
					['Hepatitis/Jaundice','Hepatitis/Jaundice'],
					['Kidney failure','Kidney failure']
				],
				'alt1' => [
          ['Kidney failure','0'],
          ['Hepatitis, Skin rash','5'],
          ['Treatment failure','8']
				],
				'alt2'=> [
          ['Kidney failure','2'],
          ['Hepatitis, Skin rash','NS'],
          ['Treatment failure','NS']
				]},
			'7' =>{ 'adverse' =>[
          ['Nausia, vomiting','Nausia, vomiting'],
          ['Kidney failure','Kidney failure'],
          ['Jaundice','Jaundice']
				],
				'contraindications' => [
					['Kidney failure','Kidney failure'],
					['Patient on rifampicin','Patient on rifampicin'],
          ['Hepatitis/Jaundice','Hepatitis/Jaundice']
				],
				'alt1' => [
          ['Nausia, vomiting','NS'],
          ['Kidney failure','8'],
          ['Jaundice','TDF/3TC + LPV/r']
				],
				'alt2'=> [
          ['Nausia, vomiting','None'],
          ['Renal failure','NS'],
          ['Jaundice','None']
				]},
			'8' => { 'adverse' => [
          ['Nausia, vomiting','Nausia, vomiting'],
          ['Anemia','Anemia'],
          ['Jaundice', 'Jaundice']
				],
				'contraindications' => [
					['Anemia <8g/dl','Anemia <8g/dl'],
          ['Patient on rifampicin','Patient on rifampicin'],
          ['Hepatitis/Jaundice','Hepatitis/Jaundice']
				],
				'alt1' => [
          ['Nausia, vomiting','NS'],
          ['Anemia','7'],
          ['Jaundice','AZT/3TC + LPV/r']
				],
				'alt2'=> [
          ['Nausia, vomiting','None'],
          ['Anemia','9'],
          ['Jaundice','None']
				]},
			'9' => { 'adverse' =>[
          ['Fever, Body pains, Vomiting, Cough', 'Fever, Body pains, Vomiting, Cough'],
          ['Diarrhoea, Vomiting','Diarrhoea, Vomiting']
				],
				'contraindications' => [
					['ABC hypersensitivity','ABC hypersensitivity']
				],
				'alt1' => [
          ['Fever, Body pains, Vomiting, Cough', '7'],
          ['Diarrhoea, Vomiting','NS']
				],
				'alt2'=> [
          ['Fever, Body pains, Vomiting, Cough', '8'],
          ['Diarrhoea, Vomiting','None']
				]
      },
      '10' => { 'adverse' =>[
          ['Kidney failure', 'Kidney failure'],
          ['Diarrhoea, vomiting, dizziness, headache', 'Diarrhoea, vomiting, dizziness, headache'],
          ['Treatment failure', 'Treatment failure']
				],
				'contraindications' => [
					['Kidney failure', 'Kidney failure']
				],
				'alt1' => [
          ['Kidney failure', '11'],
          ['Diarrhoea, vomiting, dizziness, headache', '7'],
          ['Treatment failure', '12']
				],
				'alt2'=> [
          ['Kidney failure', '8'],
          ['Diarrhoea, vomiting, dizziness, headache', '8'],
          ['Treatment failure', 'None']
				]
      },
      '11' => { 'adverse' =>[
          ['Anaemia, vomiting, appetite loss', 'Anaemia, vomiting, appetite loss'],
          ['Lipodystrophy, lactic acidosis', 'Lipodystrophy, lactic acidosis'],
          ['Diarrhoea, vomiting, dizziness, headache', 'Diarrhoea, vomiting, dizziness, headache'],
          ['Treatment failure', 'Treatment failure']
				],
				'contraindications' => [
					['Anemia <8g/dl', 'Anemia <8g/dl']
				],
				'alt1' => [
          ['Anaemia, vomiting, appetite loss', '10'],
          ['Lipodystrophy, lactic acidosis', '10'],
          ['Diarrhoea, vomiting, dizziness, headache', '8'],
          ['Treatment failure', '12']
				],
				'alt2'=> [
          ['Anaemia, vomiting, appetite loss', '7'],
          ['Lipodystrophy, lactic acidosis', '7'],
          ['Diarrhoea, vomiting, dizziness, headache', '7'],
          ['Treatment failure', 'None']
				]
      },
      '12' => { 'adverse' =>[
          ['Diarrhoea, vomiting, headache, dizziness', 'Diarrhoea, vomiting, headache, dizziness'],
          ['Neuropathy', 'Neuropathy'],
          ['Rash', 'Rash'],
          ['Jaundice', 'Jaundice']
				],
				'contraindications' => [
					['', '']
				],
				'alt1' => [
          ['Diarrhoea, vomiting, headache, dizziness', 'NS'],
          ['Neuropathy', 'NS'],
          ['Rash', 'NS'],
          ['Jaundice', 'NS']
				],
				'alt2'=> [
          ['Diarrhoea, vomiting, headache, dizziness', 'None'],
          ['Neuropathy', 'None'],
          ['Rash', 'None'],
          ['Jaundice', 'None']
				]
      }

		}

	end

	def create
    #raise params[:assess_fast_track].inspect
		#raise prescribe_pyridoxine.to_yaml

		@patient = Patient.find(params[:patient_id] || session[:patient_id]) rescue nil
		session_date = (session[:datetime].to_date rescue Time.now())


    weight = @current_weight = PatientService.get_patient_attribute_value(@patient, "current_weight")
    unless params[:regimen_main].blank?
      params[:regimen] = params[:regimen_main] #This is a hack. Going back and forth when custom regimens have been selected things were crashing
    end
 
		prescribe_tb_drugs = false
		prescribe_tb_continuation_drugs = false
		prescribe_arvs = false
		prescribe_cpt = false
		prescribe_ipt = false
		clinical_notes = nil
    prescribe_pyridoxine = nil
		condoms = nil
		reason = nil
		(params[:observations] || []).each do |observation|
			if observation['concept_name'].upcase == 'PRESCRIBE DRUGS'
				prescribe_tb_drugs = ('YES' == observation['value_coded_or_text'])
				prescribe_tb_continuation_drugs = ('YES' == observation['value_coded_or_text'])
			elsif observation['concept_name'] == 'PRESCRIBE ARVS'
				prescribe_arvs = ('YES' == observation['value_coded_or_text'])
			elsif observation['concept_name'] == 'Prescribe cotramoxazole'
				prescribe_cpt = ('YES' == observation['value_coded_or_text'])
			elsif observation['concept_name'] == 'ISONIAZID'
				prescribe_ipt = ('YES' == observation['value_coded_or_text'])
			elsif observation['concept_name'] == 'CLINICAL NOTES CONSTRUCT'
				clinical_notes = observation['value_text']
			elsif observation['concept_name'] == 'CONDOMS'
				condoms = observation['value_numeric']
			elsif observation['concept_name'] == 'Reason antiretrovirals changed or stopped'
				reason = observation['value_coded_or_text']
      elsif observation['concept_name'] == "pyridoxine"
        prescribe_pyridoxine =  observation['value_coded_or_text']
			end

		end

    unless params[:drug_names].blank?
      #This is non standard regimen
      #Do not automatically create CPT/IPT prescription. It has to be manually selected from the list of drugs
      prescribe_cpt = false
      prescribe_ipt = false
    end

		if !params[:filter][:provider].blank?
			user_person_id = User.find_by_username(params[:filter][:provider]).person_id
		else
			user_person_id = current_user.person_id
		end

    unless params[:location].blank?
      Person.migrated_datetime = params['encounter']['date_created']
      Person.migrated_creator  = params['encounter']['creator'] rescue nil
      User.current = User.find(params['encounter']['creator'])
      Location.current_location = Location.find(params[:location])
    end

		user_person_id = user_person_id rescue User.find_by_user_id(current_user.user_id).person_id

    if session[:datetime]
      treatment_datetime = session_date.strftime("%Y-%m-%d 00:00:01")
    else
      treatment_datetime = session_date.strftime("%Y-%m-%d %H:%M:%S")
    end

		encounter = PatientService.current_treatment_encounter(@patient, treatment_datetime, user_person_id)

    ############################################# set next appointment interval type #########################################
    set_appointment_interval_type = nil
    optimized_hanging_pills = {}

		(params[:observations] || []).each do |observation|
			if observation['concept_name'].upcase == 'APPOINTMENT TYPE'
        Observation.create(:person_id => @patient.id, 
          :obs_datetime => encounter.encounter_datetime,
          :concept_id => ConceptName.find_by_name('Appointment type').concept_id,
          :value_text => observation[:value_coded_or_text], 
          :encounter_id => encounter.id) 

        set_appointment_interval_type = observation[:value_coded_or_text]
      end
    end

    if set_appointment_interval_type == 'Optimize - including hanging pills'
      optimized_hanging_pills = MedicationService.amounts_brought_to_clinic(@patient, session_date.to_date)
    end
    ################################################################################################### 
 
		start_date = session[:datetime] || Time.now
		arvs_buffer = 2

    unless session[:datetime].blank?
		  auto_expire_date = (session[:datetime].to_date + (params[:duration].to_i - 1).days) 
      auto_cpt_ipt_expire_date = (session[:datetime].to_date + (params[:duration].to_i - 1).days) 
    else
      auto_expire_date = (Time.now + (params[:duration].to_i - 1).days) 
      auto_cpt_ipt_expire_date = (Time.now + (params[:duration].to_i - 1).days) 
    end 
	
		auto_tb_expire_date = session[:datetime] + params[:tb_duration].to_i.days rescue Time.now + params[:tb_duration].to_i.days
		auto_tb_continuation_expire_date = session[:datetime] + params[:tb_continuation_duration].to_i.days rescue Time.now + params[:tb_continuation_duration].to_i.days


    ######################################################################################
    fast_track_status = params[:fast_track_yes_no]
    fast_track_encounter_type = EncounterType.find_by_name("FAST TRACK ASSESMENT")
    fast_track_encounter = @patient.encounters.where(["encounter_type =? AND DATE(encounter_datetime) =?",
        fast_track_encounter_type, session_date.to_date]).last
    #concept_ids = params[:fast_track_concept_ids].split(",")

    unless params[:fast_track_yes_no].blank? 
      ActiveRecord::Base.transaction do

        fast_track_encounter.void unless fast_track_encounter.blank?
        fast_track_encounter = Encounter.new
        fast_track_encounter.encounter_type = fast_track_encounter_type.encounter_type_id
        fast_track_encounter.patient_id = params[:patient_id]
        fast_track_encounter.encounter_datetime = session_date

        if params['encounter']
          unless params['encounter']['creator'].blank?
            fast_track_encounter.provider_id = params['encounter']['provider']
          end
        end
        
        fast_track_encounter.save

        params[:fast_track_concept].each do |concept_id, concept_ans|
          fast_track_encounter.observations.create({
              :person_id => params[:patient_id],
              :concept_id => concept_id,
              :value_coded => Concept.find_by_name(concept_ans).concept_id,
              :obs_datetime => fast_track_encounter.encounter_datetime
            }) unless concept_id.blank?
        end

        fast_track_encounter.observations.create({
            :person_id => @patient.patient_id,
            :concept_id => Concept.find_by_name("FAST").concept_id,
            :value_coded => Concept.find_by_name(fast_track_status).concept_id,
            :obs_datetime => encounter.encounter_datetime
          })

        fast_track_encounter.observations.create({
          :person_id => @patient.patient_id,
          :concept_id => Concept.find_by_name("ASSESS FOR FAST TRACK?").concept_id,
          :value_coded => Concept.find_by_name("YES").concept_id,
          :obs_datetime => encounter.encounter_datetime
        })
      end
      
    end if params[:assess_fast_track] == 'YES'
    
    #This part will execute when Assess Fast Track is NO
    if params[:assess_fast_track] == 'NO'
      fast_track_encounter.void unless fast_track_encounter.blank?
      fast_track_encounter = Encounter.new
      fast_track_encounter.encounter_type = fast_track_encounter_type.encounter_type_id
      fast_track_encounter.patient_id = params[:patient_id]
      fast_track_encounter.encounter_datetime = session_date

      if params['encounter']
        unless params['encounter']['creator'].blank?
          fast_track_encounter.provider_id = params['encounter']['provider']
        end
      end

      fast_track_encounter.save

      fast_track_encounter.observations.create({
          :person_id => @patient.patient_id,
          :concept_id => Concept.find_by_name("ASSESS FOR FAST TRACK?").concept_id,
          :value_coded => Concept.find_by_name("NO").concept_id,
          :obs_datetime => encounter.encounter_datetime
        })
    end

    ######################################################################################
		orders = RegimenDrugOrder.where(regimen_id:  params[:tb_regimen])
		ActiveRecord::Base.transaction do
			# Need to write an obs for the regimen they are on, note that this is ARV
			# Specific at the moment and will likely need to have some kind of lookup
			# or be made generic
			obs = Observation.create(
				:concept_name => "WHAT TYPE OF TUBERCULOSIS REGIMEN",
				:person_id => @patient.person.person_id,
				:encounter_id => encounter.encounter_id,
				:value_coded => params[:tb_regimen_concept_id],
				:obs_datetime => start_date) if prescribe_tb_drugs
			orders.each do |order|
				drug = Drug.find(order.drug_inventory_id)
				regimen_name = (order.regimen.concept.concept_names.typed("SHORT").first || order.regimen.concept.name).name
				DrugOrder.write_order(
					encounter,
					@patient,
					obs,
					drug,
					start_date,
					auto_tb_expire_date,
					order.dose,
					order.frequency,
					order.prn,
  				"#{drug.name}: #{order.instructions} (#{regimen_name})",
					order.equivalent_daily_dose)
			end if prescribe_tb_drugs
		end

		orders = RegimenDrugOrder.where(regimen_id: params[:tb_continuation_regimen])
		ActiveRecord::Base.transaction do
			# Need to write an obs for the regimen they are on, note that this is ARV
			# Specific at the moment and will likely need to have some kind of lookup
			# or be made generic
			obs = Observation.create(
				:concept_name => "WHAT TYPE OF TUBERCULOSIS REGIMEN",
				:person_id => @patient.person.person_id,
				:encounter_id => encounter.encounter_id,
				:value_coded => params[:tb_continuation_regimen_concept_id],
				:obs_datetime => start_date) if prescribe_tb_continuation_drugs
			orders.each do |order|
				drug = Drug.find(order.drug_inventory_id)
				regimen_name = (order.regimen.concept.concept_names.typed("SHORT").first || order.regimen.concept.name).name
				DrugOrder.write_order(
					encounter,
					@patient,
					obs,
					drug,
					start_date,
					auto_tb_continuation_expire_date,
					order.dose,
					order.frequency,
					order.prn,
					"#{drug.name}: #{order.instructions} (#{regimen_name})",
					order.equivalent_daily_dose)
			end if prescribe_tb_continuation_drugs
		end

    (params[:htn_drugs] || []).each do |drg|

      if !params[:duration].blank?
        auto_htn_expire_date = session[:datetime] + params[:duration].to_i.days +
          arvs_buffer.days rescue Time.now + params[:duration].to_i.days + arvs_buffer.days
      else
        auto_htn_expire_date = session[:datetime] + params[:cpt_duration].to_i.days +
          arvs_buffer.days rescue Time.now + params[:cpt_duration].to_i.days + arvs_buffer.days
      end

      drug = Drug.find_by_name(drg)
      DrugOrder.write_order(encounter, @patient, nil, drug, start_date, auto_htn_expire_date,
        1,"OD",false, "#{drug.name}: Once a day", 1)
    end

    if (!params[:htn_drugs].blank?)
      ht_program_id = Program.find_by_name("HYPERTENSION PROGRAM").id
      program = PatientProgram.where(["DATE(date_enrolled) <= ? AND patient_id = ? AND program_id = ?",
          (session[:datetime].to_date rescue Date.today), @patient.id,
          ht_program_id]).last

      state = PatientState.where(
        ["patient_program_id = ? AND DATE(start_date) <= ?",
          program.id, (session[:datetime].to_date rescue Date.today)]).last rescue nil
      current_state = ConceptName.find_by_concept_id(state.program_workflow_state.concept_id).name rescue nil

      if state.present? && (current_state.downcase.strip != "on treatment")
        on_treatment_state = ProgramWorkflowState.where(
          ["program_workflow_id = ? AND concept_id = ?",
            ProgramWorkflow.where(["program_id = ?",
																	 ht_program_id]).first.id,
            Concept.find_by_name("On Treatment").id]).last.id

        PatientState.create(:patient_program_id => program.id,
          :start_date => (session[:datetime].to_date rescue Date.today),
          :state => on_treatment_state)
        state.update_attributes(:end_date => (session[:datetime].to_date rescue Date.today))
      end
    end

    params[:regimen] = params[:regimen_all] if ! params[:regimen_all].blank?
		reduced = false
    #weight = @current_weight = PatientService.get_patient_attribute_value(@patient, "current_weight")
    regimen_concept_id_all = (params[:regimen_concept_id_all].reject(&:empty?) rescue []) #remove empty elements
    unless regimen_concept_id_all.blank?
      drug_names = params[:drug_names].keys
      drug_ids = Drug.where(["name IN (?)", drug_names]).map(&:drug_id)
      regimen_name = MedicationService.regimen_interpreter(drug_ids)
      regimen_type = drug_names.join(' ')
      
      orders = params[:drug_names].map do |d_name, values|
        {
          :drug_name => d_name,
          :am => values["am"],
          :pm => values["pm"],
          :units => "tabs",
          :drug_id => Drug.find_by_name(d_name).drug_id,
          :regimen_index => regimen_name
        }
      end
    else
      ########################### if patient is being initiated/re started and if given regimen that contains NVP ##########
      on_tb_treatment = Observation.where(["person_id = ? AND concept_id = ?
        AND obs_datetime <= ?", @patient.patient_id, ConceptName.find_by_name('TB treatment').concept_id,
          session_date.strftime('%Y-%m-%d 23:59:59')]).order("obs_datetime DESC").last.to_s #rescue ''
      
      if on_tb_treatment.match(/Yes/i)
        on_tb_treatment = true 
      else
        on_tb_treatment = false
      end

      unless params[:regimen_main].blank?
        params[:regimen] = params[:regimen_main]
      end
      
      patient_initiated =  PatientService.patient_initiated(@patient.patient_id, session_date)
      if patient_initiated.match(/Re-initiated|Initiation/i)
        orders = MedicationService.regimen_medications(params[:regimen], weight, true, on_tb_treatment)
      elsif on_tb_treatment == true
        orders = MedicationService.regimen_medications(params[:regimen], weight, false, on_tb_treatment)
      else
        orders = MedicationService.regimen_medications(params[:regimen], weight)
      end
      #######################################################################################################################

      regimen_type = MedicationService.regimen_medications(params[:regimen], weight).collect{|d|d[:drug_name]}.join(' ')
    end

    regimen_drug_ids = orders.collect{|o|o[:drug_id]}
    selected_regimen = MedicationService.regimen_interpreter(regimen_drug_ids) if prescribe_arvs
    #raise orders.inspect
		#orders = RegimenDrugOrder.all(:conditions => {:regimen_id => params[:regimen]})
		ActiveRecord::Base.transaction do
			# Need to write an obs for the regimen they are on, note that this is ARV
			# Specific at the moment and will likely need to have some kind of lookup
			# or be made generic
			#selected_regimen = Regimen.find(params[:regimen]) if prescribe_arvs
			obs = Observation.create(
				:concept_name => "REGIMEN CATEGORY",
				:person_id => @patient.person.person_id,
				:encounter_id => encounter.encounter_id,
				:value_text => selected_regimen,
				:obs_datetime => start_date) if prescribe_arvs
=begin
			obs = Observation.create(
				:concept_name => "WHAT TYPE OF ANTIRETROVIRAL REGIMEN",
				:person_id => @patient.person.person_id,
				:encounter_id => encounter.encounter_id,
				:value_coded => params[:regimen_concept_id],
				:obs_datetime => start_date) if prescribe_arvs
=end
      
      obs = Observation.create(
				:concept_name => "WHAT TYPE OF ANTIRETROVIRAL REGIMEN",
				:person_id => @patient.person.person_id,
				:encounter_id => encounter.encounter_id,
				:value_text => regimen_type,
				:obs_datetime => start_date) if prescribe_arvs

			orders.each do |order|
        drug = Drug.find(order[:drug_id])
        morning_tabs = order[:am]
        evening_tabs = order[:pm]

        instructions = "#{drug.name}:- Morning: #{morning_tabs} tab(s), Evening: #{evening_tabs} tabs"
        frequency = "ONCE A DAY (OD)"
        equivalent_daily_dose = morning_tabs.to_f + evening_tabs.to_f
        dose = morning_tabs if evening_tabs.to_i == 0
        dose = evening_tabs if morning_tabs.to_i == 0
        
        if (morning_tabs.to_i > 0 && evening_tabs.to_i > 0)
          frequency = "TWICE A DAY (BD)"
          dose = (morning_tabs.to_f + evening_tabs.to_f)/2
        end
        prn = 0
			
        #################### Here we check if its an 'Optimize' prescrition, if yes we subtract the hanging doses to the
        ## prescribe dose

        ##############################################################################################################3

        DrugOrder.write_order(
          encounter,
          @patient,
          obs,
          drug,
          start_date,
          auto_expire_date,
          dose,
          frequency,
          prn,
          instructions,
          equivalent_daily_dose)

			end if prescribe_arvs
		end

		['CPT STARTED','ISONIAZID'].each do | concept_name |
			if concept_name == 'ISONIAZID'
				concept = 'NO' unless prescribe_ipt
				concept = 'YES' if prescribe_ipt
			else
				concept = 'NO' unless prescribe_cpt
				concept = 'YES' if prescribe_cpt
			end
			yes_no = ConceptName.find_by_name(concept)
			obs = Observation.create(
				:concept_name => concept_name ,
				:person_id => @patient.person.person_id ,
				:encounter_id => encounter.encounter_id ,
				:value_coded => yes_no.concept_id ,
				:obs_datetime => start_date)

			next if concept == 'NO'
      weight = @current_weight = PatientService.get_patient_attribute_value(@patient, "current_weight")
      if ! params[:cpt_duration].blank?
        auto_cpt_ipt_expire_date = session[:datetime] + params[:cpt_duration].to_i.days + arvs_buffer.days rescue Time.now + params[:cpt_duration].to_i.days + arvs_buffer.days
      end

			if concept_name == 'CPT STARTED'
				if params[:cpt_mgs] == "960"
					drug = Drug.find_by_name('Cotrimoxazole (960mg)')
        elsif params[:cpt_mgs] == "120"
          drug = Drug.find_by_name('TMP/SMX (Cotrimoxazole 120mg tablet)')
        elsif params[:cpt_mgs] == "240"
          drug = Drug.find_by_name('TMP/SMX (Cotrimoxazole 240mg tablet)')
				else
					drug = Drug.find_by_name('Cotrimoxazole (480mg tablet)')
				end

        order = MedicationService.other_medications('Cotrimoxazole', weight).first

      else
				if params[:ipt_mgs] == "300"
          drug = Drug.find_by_name('INH or H (Isoniazid 300mg tablet)')
        elsif params[:ipt_mgs] == "250"
          drug = Drug.find_by_name('INH or H (Isoniazid 250mg tablet)')
        elsif params[:ipt_mgs] == "200"
          drug = Drug.find_by_name('INH or H (Isoniazid 200mg tablet)')
        elsif params[:ipt_mgs] == "150"
          drug = Drug.find_by_name('INH or H (Isoniazid 150mg tablet)')
        else
          drug = Drug.find_by_name('INH or H (Isoniazid 100mg tablet)')
				end

        order = MedicationService.other_medications('Isoniazid', weight).first

			end

      morning_tabs = order[:am]
      evening_tabs = order[:pm]

      instructions = "#{drug.name}:- Morning: #{morning_tabs} tab(s), Evening: #{evening_tabs} tabs"
      frequency = "ONCE A DAY (OD)"
      equivalent_daily_dose = morning_tabs.to_f + evening_tabs.to_f
      dose = morning_tabs if evening_tabs.to_i == 0
      dose = evening_tabs if morning_tabs.to_i == 0

      if (morning_tabs.to_i > 0 && evening_tabs.to_i > 0)
        frequency = "TWICE A DAY (BD)"
        dose = (morning_tabs.to_f + evening_tabs.to_f)/2
      end
      
      prn = 0

      DrugOrder.write_order(
        encounter,
        @patient,
        obs,
        drug,
        start_date,
        auto_cpt_ipt_expire_date,
        dose,
        frequency,
        prn,
        instructions,
        equivalent_daily_dose
      )
      
		end

    unless prescribe_pyridoxine .blank?
      if ! params[:cpt_duration].blank?
        #params[:cpt_duration] =  params[:duration]
        auto_cpt_ipt_expire_date = session[:datetime] + params[:cpt_duration].to_i.days + arvs_buffer.days rescue Time.now + params[:cpt_duration].to_i.days + arvs_buffer.days
      elsif prescribe_arvs
        auto_cpt_ipt_expire_date = auto_expire_date
      elsif prescribe_tb_drugs
        auto_cpt_ipt_expire_date = auto_tb_expire_date
      else
        auto_cpt_ipt_expire_date = ((session[:datetime] + params[:duration].to_i.days + arvs_buffer.days rescue Time.now + params[:duration].to_i.days + arvs_buffer.days) rescue auto_tb_continuation_expire_date)
      end
      concept_name = "pyridoxine"
      yes_no = ConceptName.find_by_name(prescribe_pyridoxine)
      obs = Observation.create(
				:concept_name => concept_name ,
				:person_id => @patient.person.person_id ,
				:encounter_id => encounter.encounter_id ,
				:value_coded => yes_no.concept_id ,
				:obs_datetime => start_date)

      if params[:pyridoxine_value] == "50"
        drug = Drug.find_by_name('Pyridoxine (50mg)')
      else
        drug = Drug.find_by_name('Pyridoxine (25mg)')
      end unless params[:pyridoxine_value].blank?

      unless params[:pyridoxine_value].blank?

        weight = @current_weight = PatientService.get_patient_attribute_value(@patient, "current_weight")
        regimen_id = Regimen.where(['min_weight <= ? AND max_weight >= ? AND concept_id = ?', weight, weight, drug.concept_id]).first.regimen_id
        orders = RegimenDrugOrder.where(regimen_id: regimen_id, drug_inventory_id:  drug.id)
      end
      #=begin
      orders.each do |order|
        regimen_name = (order.regimen.concept.concept_names.typed("SHORT").first || order.regimen.concept_names.typed("FULLY_SPECIFIED").first).name
        DrugOrder.write_order(
          encounter,
          @patient,
          obs,
          drug,
          start_date,
          auto_cpt_ipt_expire_date,
          order.dose,
          order.frequency,
          order.prn,
          "#{drug.name}: #{order.instructions} (#{regimen_name})",
          order.equivalent_daily_dose)
      end unless params[:pyridoxine_value].blank?
    end

		obs = Observation.create(
			:concept_name => "Reason antiretrovirals changed or stopped",
			:person_id => @patient.person.person_id,
			:encounter_id => encounter.encounter_id,
			:value_text => reason,
			:obs_datetime => start_date) if !reason.blank?

		obs = Observation.create(
			:concept_name => "CONDOMS",
			:person_id => @patient.person.person_id,
			:encounter_id => encounter.encounter_id,
			:value_numeric => condoms,
			:obs_datetime => start_date) if !condoms.blank?

		if !params[:transfer_data].nil?
			transfer_out_patient(params[:transfer_data][0])
		end


    if set_appointment_interval_type == 'Optimize - including hanging pills' #and not optimized_hanging_pills.blank?	
      MedicationService.adjust_order_end_dates(encounter.orders, optimized_hanging_pills)
    end

		# Send them back to treatment for now, eventually may want to go to workflow
		redirect_to "/patients/treatment_dashboard?patient_id=#{@patient.id}"
	end

	def suggested
		session_date = session[:datetime].to_date rescue Date.today
    begin
		  patient_program = PatientProgram.find(params[:id])
    rescue
		  patient_program = PatientProgram.find(session[:active_patient_id])
    end

		render :layout => false and return unless patient_program
		current_weight = PatientService.get_patient_attribute_value(patient_program.patient, "current_weight", session_date)
		#@options = MedicationService.regimen_options(current_weight, patient_program.program)
    @options = ['']
    MedicationService.moh_arv_regimen_options(current_weight).each do |option|
      @options << option
    end
		#tmp = []
    #new_guide_lines_start_date = GlobalProperty.find_by_property('new.art.start.date').property_value.to_date rescue nil

		render :layout => false
	end

  def suggest_all
    medications = Drug.select("drug.*, i.*").joins("INNER JOIN moh_regimen_ingredient i ON i.drug_inventory_id = drug.drug_id"
		                          ).group('drug.drug_id')

    session_date = session[:datetime].to_date rescue Date.today
    patient = Patient.find(params[:patient_id])
    allergic_to_sulphur = Patient.allergic_to_sulpher(@patient, session_date)

    if allergic_to_sulphur == 'Yes'
      prescribe_cpt_set = false
    else
      prescribe_cpt_set = prescribe_medication_set(patient, session_date, 'CPT')
    end
    prescribe_ipt_set = prescribe_medication_set(patient, session_date, 'Isoniazid')

    if prescribe_cpt_set == true
      cpt_drug_names = ['TMP/SMX (Cotrimoxazole 120mg tablet)', 'TMP/SMX (Cotrimoxazole 240mg tablet)',
        'Cotrimoxazole (480mg tablet)', 'Cotrimoxazole (960mg)'
      ]
      cpt_drugs = Drug.where(["name IN (?)", cpt_drug_names])
      cpt_drugs.each do |cpt_drug|
        medications << cpt_drug
      end
    end

    if prescribe_ipt_set == true
      pyridoxine_ipt_drug_names = ['INH or H (Isoniazid 100mg tablet)', 'Pyridoxine (25mg)']
      pyridoxine_ipt_drugs = Drug.where(["name IN (?)", pyridoxine_ipt_drug_names])
      pyridoxine_ipt_drugs.each do |drug|
        medications << drug
      end
    end
    
    @options = (medications || []).map do | m |
      [m.name , m.drug_id ]
    end

		render :layout => false
	end

  def custom_regimen_options(patient)
    medications = Drug.select("drug.*, i.*").joins("INNER JOIN moh_regimen_ingredient i
      ON i.drug_inventory_id = drug.drug_id").group('drug.drug_id').to_a

    session_date = session[:datetime].to_date rescue Date.today

    allergic_to_sulphur = Patient.allergic_to_sulpher(patient, session_date)

    if allergic_to_sulphur == 'Yes'
      prescribe_cpt_set = false
    else
      prescribe_cpt_set = prescribe_medication_set(patient, session_date, 'CPT')
    end
    prescribe_ipt_set = prescribe_medication_set(patient, session_date, 'Isoniazid')

    if prescribe_cpt_set == true
      cpt_drug_names = ['TMP/SMX (Cotrimoxazole 120mg tablet)', 'TMP/SMX (Cotrimoxazole 240mg tablet)',
        'Cotrimoxazole (480mg tablet)', 'Cotrimoxazole (960mg)'
      ]
      cpt_drugs = Drug.where(["name IN (?)", cpt_drug_names])
      cpt_drugs.each do |cpt_drug|
        medications << cpt_drug
      end
    end

    if prescribe_ipt_set == true
      pyridoxine_ipt_drug_names = ['INH or H (Isoniazid 100mg tablet)', 'Pyridoxine (25mg)']
      pyridoxine_ipt_drugs = Drug.where(["name IN (?)", pyridoxine_ipt_drug_names])
      pyridoxine_ipt_drugs.each do |drug|
        medications << drug
      end
    end

    medication_options = (medications || []).map do | m |
      [m.name , m.drug_id ]
    end

    return medication_options.sort_by{|k, v|k}
	end
  
	def dosing
		@patient = Patient.find(params[:patient_id] || session[:patient_id]) rescue nil
		@criteria = Regimen.criteria(PatientService.get_patient_attribute_value(@patient, "current_weight")).where(
				concept_id: params[:id]).includes(:regimen_drug_orders)
		@options = @criteria.map do |r|
			[r.regimen_id, r.regimen_drug_orders.map(&:to_s).join('; ')]
		end
		render :layout => false
	end

  def dosing_all
		@patient = Patient.find(params[:patient_id] || session[:patient_id]) rescue nil
    @criteria = Regimen.where(['program_id = ? AND concept_id =?', 1, params[:id]]
		                          ).includes(:regimen_drug_orders).order('regimen_index')

    #	@criteria = Regimen.criteria(PatientService.get_patient_attribute_value(@patient, "current_weight")).all(:conditions => {:concept_id => params[:id]}, :include => :regimen_drug_orders)

		@options = @criteria.map do |r|
			[r.regimen_id, r.regimen_drug_orders.map(&:to_s).join('; ')]
		end
		render :layout => false
	end

	def formulations
    @patient = Patient.find(params[:patient_id] || session[:patient_id]) rescue nil
    session_date = session[:datetime].to_date rescue Date.today
    current_weight = PatientService.get_patient_attribute_value(@patient, "current_weight", session_date)
   
    patient_initiated =  PatientService.patient_initiated(@patient.patient_id, session_date)
      
    on_tb_treatment = Observation.where(["person_id = ? AND concept_id = ?
      AND obs_datetime <= ?", @patient.patient_id, ConceptName.find_by_name('TB treatment').concept_id,
        session_date.to_date.strftime('%Y-%m-%d 23:59:59')]).order("obs_datetime DESC").last.to_s #rescue ''
    
    if on_tb_treatment.match(/Yes/i)
      on_tb_treatment = true 
    else
      on_tb_treatment = false
    end
   
    ########################### if patient is being initiated/re started and if given regimen that contains NVP ##########
    if patient_initiated.match(/Re-initiated|Initiation/i)
      regimen_medications = MedicationService.regimen_medications(params[:id], current_weight, true, on_tb_treatment)
    else
      regimen_medications = MedicationService.regimen_medications(params[:id], current_weight, false, on_tb_treatment)
    end
    #######################################################################################################################


    ################################################################################################################
		@allergic_to_sulphur = Patient.allergic_to_sulpher(@patient, session_date) #chunked
    @fast_track_patient = fast_track_patient?(@patient, session_date)
    fast_track_obs_date = fast_track_obs_date(@patient, session_date)

    if @fast_track_patient
      unless fast_track_obs_date.blank?
        if (fast_track_obs_date < session_date)
          #Ignore this logic if Fast Track has been enrolled today
          if (Patient.cpt_prescribed_in_the_last_prescription?(@patient, session_date))
            dose = MedicationService.other_medications('Cotrimoxazole', current_weight)
            regimen_medications = (regimen_medications + dose) unless dose.blank?
          end
      
          if (Patient.ipt_prescribed_in_the_last_prescription?(@patient, session_date))
            dose = MedicationService.other_medications('Isoniazid', current_weight)
            regimen_medications = (regimen_medications + dose) unless dose.blank?
            category = regimen_medications.last[:category] rescue nil
            drug = Drug.find_by_name('Pyridoxine (25mg)')

            pyridoxine_regimen_drug_order = RegimenDrugOrder.where(["drug_inventory_id = ?", drug.id])

            (pyridoxine_regimen_drug_order || []).each do |r|
              next unless current_weight.to_f >= r.regimen.min_weight.to_f && r.regimen.max_weight.to_f <= current_weight.to_f
              pyridoxine_dose = [{
                  :drug_name => r.drug.name,
                  :am => 0,
                  :pm => r.dose,
                  :units => 'Tab(s)',
                  :drug_id => r.drug.id,
                  :regimen_index => nil,
                  :category => 'A'
                }]
              regimen_medications = (regimen_medications + pyridoxine_dose) #Prescribe pyridoxine when IPT is selected
            end
          end
        end
      end
    end
    
    if @allergic_to_sulphur == 'Yes'
      @prescribe_medication_set = false
    else
      @prescribe_cpt_set = prescribe_medication_set(@patient, session_date, 'CPT')
    end
    @prescribe_ipt_set = prescribe_medication_set(@patient, session_date, 'Isoniazid')

    if @prescribe_cpt_set == true
      dose = MedicationService.other_medications('Cotrimoxazole', current_weight)
      unless dose.blank?
        regimen_medications = (regimen_medications + dose)
      end
    end


    if @prescribe_ipt_set == true
      dose = MedicationService.other_medications('Isoniazid', current_weight)
      unless dose.blank?
        regimen_medications = (regimen_medications + dose)
      end
      category = regimen_medications.last[:category] rescue nil
      drug = Drug.find_by_name('Pyridoxine (25mg)')
      
      pyridoxine_regimen_drug_orders = RegimenDrugOrder.where(["drug_inventory_id = ?", drug.id])

      (pyridoxine_regimen_drug_orders || []).each do |r|
        next unless current_weight.to_f >= r.regimen.min_weight.to_f && current_weight.to_f <= r.regimen.max_weight.to_f
        pyridoxine_dose = [{
            :drug_name => drug.name,
            :am => 0,
            :pm => r.dose,
            :units => 'Tab(s)',
            :drug_id => drug.id,
            :regimen_index => nil,
            :category => 'A'
          }]
        regimen_medications = (regimen_medications + pyridoxine_dose) #Prescribe pyridoxine when IPT is selected
      end
      
    end
    ################################################################################################################


    @options = (regimen_medications || []).each do | r |
      [r[:drug_name] , r[:am] , r[:pm], r[:units] , r[:regimen_index] , r[:category]]
    end

    render plain: @options.to_json
	end

  def formulations_cpt_or_ipt
    @patient = Patient.find(params[:patient_id] || session[:patient_id]) rescue nil
    session_date = session[:datetime].to_date rescue Date.today
    current_weight = PatientService.get_patient_attribute_value(@patient, "current_weight", session_date)
    regimen_medications = []

		@allergic_to_sulphur = Patient.allergic_to_sulpher(@patient, session_date)
    if @allergic_to_sulphur == 'Yes'
      @prescribe_medication_set = false
    else
      @prescribe_cpt_set = prescribe_medication_set(@patient, session_date, 'CPT')
    end
    @prescribe_ipt_set = prescribe_medication_set(@patient, session_date, 'Isoniazid')

    if @prescribe_cpt_set == true
      dose = MedicationService.other_medications('Cotrimoxazole', current_weight)
      regimen_medications = (regimen_medications + dose) unless dose.blank?
    end

    if @prescribe_ipt_set == true
      dose = MedicationService.other_medications('Isoniazid', current_weight)
      regimen_medications = (regimen_medications + dose) unless dose.blank?
      category = regimen_medications.last[:category] rescue nil
      drug = Drug.find_by_name('Pyridoxine (25mg)')

      pyridoxine_dose = [{
          :drug_name => 'Pyridoxine (25mg)',
          :am => '0',
          :pm => '1',
          :units => 'Tab(s)',
          :drug_id => drug.drug_id,
          :regimen_index => nil,
          :category => category
        }]

      regimen_medications = (regimen_medications + pyridoxine_dose) #Prescribe pyridoxine when IPT is selected
    end

    ################################################################################################################

    @options = (regimen_medications || []).each do | r |
      [r[:drug_name] , r[:am] , r[:pm], r[:units] , r[:regimen_index] , r[:category]]
    end
    
    render plain: @options.to_json
  end

  def formulations_all
    names = params[:names].split('::')
    medications = Drug.select("drug.*, i.*").where(["drug.name IN(?)", names]).joins(
				"INNER JOIN moh_regimen_ingredient i ON i.drug_inventory_id = drug.drug_id"
		).group("drug.drug_id")
    names.each do |drug_name|
      if (drug_name.match(/Cotrimoxazole|Isoniazid|Pyridoxine/i))
        #These drugs are not in moh_regimen_ingredient
        medications = [] if medications.blank?
        drug = Drug.find_by_name(drug_name)
        medications << drug
      end
    end

    @options = (medications || []).map do | m |
      [m.name , m.units, m.drug_id ]
    end
    render plain: @options.to_json

	end

  def recommend_duration(total_days, equivalent_daily_dose, current_stock, drug_pack_size)
    current_stock = (current_stock * drug_pack_size) #converting tins to tablets
    durations = ['4 days','1 week','2 weeks','1 month','2 months','3 months',
      '4 months','5 months','6 months','7 months','8 months']
    hash = {}
    durations.each do |duration|
      days = (((duration.to_i) * 7)) if duration.match(/week/i)
      days = 4 if duration.match(/days/i)
      days = (((duration.to_i) * 28)) if duration.match(/month/i)
      hash[days] = duration
    end

    sorted_durations = hash.sort_by{|k, v| k } #sorting in ascending order by key
    filtered_durations = []
    sorted_durations.each do |k, v|
      break if k > total_days
      filtered_durations << [k, v]
    end
    filtered_durations = filtered_durations.reverse #sorting in descending order by key

    insufficient_stock = true
    filtered_durations.each do |k, v|
      required_days = k
      amount_prescribed = (required_days * equivalent_daily_dose)
      next if (amount_prescribed > current_stock)
      insufficient_stock = false
      return v #days/weeks/months
    end

    return 'No stock' if insufficient_stock
  end

  def check_drug_stock_levels
    drug_id = params[:drug_id]
    data = {}
    current_stock = Pharmacy.latest_drug_stock(drug_id).to_i
    drug_units = Drug.find(drug_id).units
    data["current_stock"] = current_stock
    data["drug_units"] = drug_units
    render :json => data and return
  end

  def check_stock_levels
    patient = Patient.find(params[:patient_id])
    #orders = RegimenDrugOrder.all(:conditions => {:regimen_id => params[:regimen]})
    weight = PatientService.get_patient_attribute_value(patient, "current_weight")
    orders = MedicationService.regimen_medications(params[:regimen], weight)
    drug_details = {}
    arvs_buffer = 2
    reduced = false

    orders.each do |order|
      drug = Drug.find(order[:drug_id])
      drug_name = drug.name
      drug_id = drug.id
      drug_pack_size = Pharmacy.pack_size(drug_id)
      current_stock = (Pharmacy.latest_drug_stock(drug_id)/drug_pack_size).to_i #In tins

      morning_tabs = order[:am]
      evening_tabs = order[:pm]
      equivalent_daily_dose = morning_tabs.to_f + evening_tabs.to_f

      duration = (params[:duration].to_i + arvs_buffer)

      #if order.regimen.concept.shortname.upcase.match(/STARTER PACK/i) and !reduced
      #reduced = true
      #duration = (params[:duration].to_i + 1)
      #end

      required_amount = (equivalent_daily_dose * duration)
      required_amount = DrugOrder.calculate_complete_pack(drug, required_amount)
      drug_details[drug_name] = {}
      drug_details[drug_name]["required_amount"] = required_amount #in tabs
      drug_details[drug_name]["current_stock"] = current_stock # in tins
      drug_details[drug_name]["drug_pack_size"] = drug_pack_size
      if (required_amount > (current_stock * drug_pack_size)) #comparing tabs to tabs
        drug_details[drug_name]["low_stock_warning"] = true
        drug_details[drug_name]["recommended_duration"] = recommend_duration(duration, equivalent_daily_dose, current_stock, drug_pack_size)
      end

    end

    render :json => drug_details and return
  end

  def drug_stock(patient, concept_id)
		stock = {}
		if (CoreService.get_global_property_value('activate.drug.management').to_s == "true" rescue false)
      regimens = Regimen.criteria(PatientService.get_patient_attribute_value(patient, "current_weight")).includes(:regimen_drug_orders).where({:concept_id => concept_id})
      regimens.each do | r |
        r.regimen_drug_orders.each do | order |
          drug = order.drug

          drug_pack_size = Pharmacy.pack_size(drug.id)
          current_stock = (Pharmacy.latest_drug_stock(drug.id)/drug_pack_size).to_i #In tins
          consumption_rate = Pharmacy.average_drug_consumption(drug.id)

          stock_out_days = ((current_stock * drug_pack_size)/consumption_rate).to_i rescue 0 #To avoid division by zero error when consumption_rate is zero
          estimated_stock_out_date = (Date.today + stock_out_days).strftime('%d-%b-%Y')
          estimated_stock_out_date = "(N/A)" if (consumption_rate.to_i <= 0)
          estimated_stock_out_date = "Stocked out" if (current_stock <= 0) #We don't want to estimate the stock out date if there is no stock available

          stock[drug.id] = {}
          stock[drug.id]["drug_name"] = drug.name
          stock[drug.id]["current_stock"] = current_stock
          stock[drug.id]["consumption_rate"] = consumption_rate.to_f.round(1)
          stock[drug.id]["estimated_stock_out_date"] = estimated_stock_out_date
          stock[drug.id]["drug_pack_size"] = drug_pack_size
        end
      end
		end
    stock
  end

  def cpt_drug_stock

		stock = {}
		if (CoreService.get_global_property_value('activate.drug.management').to_s == "true" rescue false)
      required_cpt = ["Cotrimoxazole (480mg tablet)", "Cotrimoxazole (960mg)"]
      required_cpt.each do | name |
        drug = Drug.find_by_name(name)

        drug_pack_size = Pharmacy.pack_size(drug.id)
        current_stock = (Pharmacy.latest_drug_stock(drug.id)/drug_pack_size).to_i #In tins
        consumption_rate = Pharmacy.average_drug_consumption(drug.id)

        stock_out_days = ((current_stock * drug_pack_size)/consumption_rate).to_i rescue 0 #To avoid division by zero error when consumption_rate is zero
        estimated_stock_out_date = (Date.today + stock_out_days).strftime('%d-%b-%Y')
        estimated_stock_out_date = "(N/A)" if (consumption_rate.to_i <= 0)
        estimated_stock_out_date = "Stocked out" if (current_stock <= 0) #We don't want to estimate the stock out date if there is no stock available

        stock[drug.id] = {}
        stock[drug.id]["drug_name"] = drug.name
        stock[drug.id]["current_stock"] = current_stock
        stock[drug.id]["consumption_rate"] = consumption_rate.to_f.round(1)
        stock[drug.id]["estimated_stock_out_date"] = estimated_stock_out_date
        stock[drug.id]["drug_pack_size"] = drug_pack_size
      end
    end
    stock
  end

  def drug_stock_availability
    patient = Patient.find(params[:patient_id])
    #regimens = Regimen.find(:all,:order => 'regimen_index',:conditions => ['concept_id =?',params[:concept_id]],:include => :regimen_drug_orders)
    #regimens = Regimen.criteria(PatientService.get_patient_attribute_value(patient, "current_weight")).all(:conditions => {:concept_id => params[:concept_id]}, :include => :regimen_drug_orders)
    stock = {}
    weight = PatientService.get_patient_attribute_value(patient, "current_weight")
    regimen_number = params[:concept_id].split(" ")[1]
    drugs = MedicationService.regimen_medications(regimen_number, weight).collect{|o|Drug.find(o[:drug_id])}
    drugs.each do | drug |

      drug_pack_size = Pharmacy.pack_size(drug.id)
      current_stock = (Pharmacy.latest_drug_stock(drug.id)/drug_pack_size).to_i #In tins
      consumption_rate = Pharmacy.average_drug_consumption(drug.id)

      stock_out_days = ((current_stock * drug_pack_size)/consumption_rate).to_i rescue 0 #To avoid division by zero error when consumption_rate is zero
      estimated_stock_out_date = (Date.today + stock_out_days).strftime('%d-%b-%Y')
      estimated_stock_out_date = "(N/A)" if (consumption_rate.to_i <= 0)
      estimated_stock_out_date = "Stocked out" if (current_stock <= 0) #We don't want to estimate the stock out date if there is no stock available

      stock[drug.id] = {}
      stock[drug.id]["drug_name"] = drug.name
      stock[drug.id]["current_stock"] = current_stock
      stock[drug.id]["consumption_rate"] = consumption_rate.to_f.round(1)
      stock[drug.id]["estimated_stock_out_date"] = estimated_stock_out_date
      stock[drug.id]["drug_pack_size"] = drug_pack_size
    end
=begin
    regimens.each do | r |
      r.regimen_drug_orders.each do | order |
        drug = order.drug

        drug_pack_size = Pharmacy.pack_size(drug.id)
        current_stock = (Pharmacy.latest_drug_stock(drug.id)/drug_pack_size).to_i #In tins
        consumption_rate = Pharmacy.average_drug_consumption(drug.id)
        
        stock_out_days = ((current_stock * drug_pack_size)/consumption_rate).to_i rescue 0 #To avoid division by zero error when consumption_rate is zero
        estimated_stock_out_date = (Date.today + stock_out_days).strftime('%d-%b-%Y')
        estimated_stock_out_date = "(N/A)" if (consumption_rate.to_i <= 0)
        estimated_stock_out_date = "Stocked out" if (current_stock <= 0) #We don't want to estimate the stock out date if there is no stock available

        stock[drug.id] = {}
        stock[drug.id]["drug_name"] = drug.name
        stock[drug.id]["current_stock"] = current_stock
        stock[drug.id]["consumption_rate"] = consumption_rate.to_f.round(1)
        stock[drug.id]["estimated_stock_out_date"] = estimated_stock_out_date
        stock[drug.id]["drug_pack_size"] = drug_pack_size
      end
    end
=end
    render :json => stock and return
  end
	# Look up likely durations for the regimen
	def durations
		@regimen = Regimen.find_by_concept_id(params[:id]).includes(:regimen_drug_orders)
		@drug_id = @regimen.regimen_drug_orders.first.drug_inventory_id rescue nil
		render plain: "No matching durations found for regimen" and return unless @drug_id

		# Grab the 10 most popular durations for this drug
		amounts = []
		orders = DrugOrder.select('DATEDIFF(orders.auto_expire_date, orders.start_date) as duration_days').where(drug_inventory_id: @drug_id).joins(
				      'LEFT JOIN orders ON orders.order_id = drug_order.order_id AND orders.voided = 0').limit(10).order('count(*)').group(
				      'drug_inventory_id, DATEDIFF(orders.auto_expire_date, orders.start_date)')

		orders.each {|order|
			amounts << "#{order.duration_days.to_f}" unless order.duration_days.blank?

		}
		amounts = amounts.flatten.compact.uniq
		render plain: ("<li>" + amounts.join("</li><li>") + "</li>").html_safe
	end

	private

	def current_regimens_for_programs
		@programs.inject({}) do |result, program|
			result[program.patient_program_id] = program.current_regimen; result
		end
	end

	def current_regimen_names_for_programs
		@programs.inject({}) do |result, program|
      result[program.patient_program_id] = program.current_regimen ? Concept.find_by_concept_id(program.current_regimen).concept_names.tagged(["short"]).map(&:name) : nil; result
		end
	end

  def transfer_out_patient(params)

    patient_program = PatientProgram.find(params[:patient_program_id])



    #we don't want to have more than one open states - so we have to close the current active on before opening/creating a new one

    current_active_state = patient_program.patient_states.last
    current_active_state.end_date = params[:current_date].to_date


    # set current location via params if given
    Location.current_location = Location.find(params[:location]) if params[:location]

    patient_state = patient_program.patient_states.build( :state => params[:current_state], :start_date => params[:current_date])


    if patient_state.save
      #Close and save current_active_state if a new state has been created
      current_active_state.save

      if patient_state.program_workflow_state.concept.fullname.upcase == 'PATIENT TRANSFERRED OUT'

        encounter = Encounter.new(params[:encounter])
        encounter.encounter_datetime = session[:datetime] unless session[:datetime].blank?
        c = encounter.save

        (params[:observations] || [] ).each do |observation|
          #for now i do this
          obs = {}
          obs[:concept_name] = observation[:concept_name]
          obs[:value_coded_or_text] = observation[:value_coded_or_text]
          obs[:encounter_id] = encounter.id
          obs[:obs_datetime] = encounter.encounter_datetime || Time.now()
          obs[:person_id] ||= encounter.patient_id
          Observation.create(obs)
        end

        observation = {}
        observation[:concept_name] = 'TRANSFER OUT TO'
        observation[:encounter_id] = encounter.id
        observation[:obs_datetime] = encounter.encounter_datetime || Time.now()
        observation[:person_id] ||= encounter.patient_id
        observation[:value_text] = Location.find(params[:transfer_out_location_id]).name rescue "UNKNOWN"
        Observation.create(observation)
      end

      date_completed = params[:current_date].to_date rescue Time.now()

      PatientProgram.update_all "date_completed = '#{date_completed.strftime('%Y-%m-%d %H:%M:%S')}'",
        "patient_program_id = #{patient_program.patient_program_id}"
    end
  end


  def current_regimen(patient_id)
	  regimen_category = Concept.find_by_name("Regimen Category")

    current_regimen = Observation.where(["concept_id = ? AND
        person_id = ? AND obs_datetime = (SELECT MAX(obs_datetime) FROM obs o
        WHERE o.person_id = #{patient_id} AND o.concept_id =#{regimen_category.id}
        AND o.voided = 0)",regimen_category.id, patient_id]).first.value_text rescue nil
  end

  def prescribe_medication_set(patient, date, medication_type)
	  prescribe_medication = Concept.find_by_name("Medication orders").concept_id
	  medication_concept = Concept.find_by_name(medication_type).concept_id

    found = Observation.where(["concept_id = ? AND person_id = ? AND value_coded = ? AND DATE(obs_datetime) = ?",
															 prescribe_medication, patient.id, medication_concept, date.to_date]).joins(:encounter).first

    return (found.blank? ? false : true)
  end

  protected


	def formulation(patient,regimen_id)
    #criteria =  Regimen.find(:all,:order => 'regimen_index',:conditions => ['concept_id =?',regimen_id],:include => :regimen_drug_orders)
		criteria = Regimen.criteria(PatientService.get_patient_attribute_value(patient, "current_weight")).includes(:regimen_drug_orders).where({:concept_id => regimen_id})
		options = []
    criteria.map do | r |
			r.regimen_drug_orders.map do | order |
				options << [order.drug.name , order.dose, order.frequency , order.units , r.id ]
			end
		end
		return options
	end

end
