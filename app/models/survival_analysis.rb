class SurvivalAnalysis

  def self.report(cohort, patient_state, min_age=nil, max_age=nil, sex = nil)
		#raise patient_state["Defaulted"].to_yaml
		program_id = Program.find_by_name('HIV PROGRAM').id
    survival_end_date = cohort.end_date.to_date ;
    survival_start_date = cohort.start_date.to_date
    displayed_date = survival_end_date
    first_registration_date = PatientProgram.where(
      ["program_id = ? AND voided = 0",program_id]
    ).order("date_enrolled ASC").first.date_enrolled.to_date rescue nil
    return if first_registration_date.blank?

    date_ranges = []

		if sex == "female"
			start_of_6_months = survival_start_date - 6.months
			end_of_6_months = survival_end_date.to_date - 6.months

			if end_of_6_months >= first_registration_date
		    date_ranges << {:start_date => start_of_6_months.to_date,
		                    :end_date   => end_of_6_months.to_date}
			end
		end

    while (survival_start_date -= 1.year) >= first_registration_date
      survival_end_date   -= 1.year
      date_ranges << {:start_date => survival_start_date,
                      :end_date   => survival_end_date
      }
    end

		survival_analysis_outcomes = {}
		views = {}
		key = ""

		date_ranges.sort_by {|x,i| x[:end_date] <=>  x[:start_date]}.each_with_index do |range, i|
			program_id = Program.find_by_name('HIV PROGRAM').id
			transferred = []; arvs =[]; stopped = []; defaulted=[]; dead=[]; unknown =[]; total = []

			if sex == "female"
         break if range[:start_date].to_date < '2011-07-01'.to_date
					states = cohort.women_outcomes(range[:start_date], range[:end_date], cohort.end_date.to_date, program_id, states = nil, min_age, max_age)
			else
					states = cohort.outcomes(range[:start_date], range[:end_date], cohort.end_date.to_date, program_id, states = nil, min_age, max_age)
			end

			if sex == "female"
				if i == 0
					key = "#{(i + 1)*6} month survival: outcomes by end of #{(range[:end_date] + (i + 1).year).strftime('%B %Y')}"
				else
					x = i - 1
					key = "#{(x + 1)*12} month survival: outcomes by end of #{(range[:end_date] + (x + 1).year).strftime('%B %Y')}"
				end
			else
				key = "#{(i + 1)*12} month survival: outcomes by end of #{(range[:end_date] + (i + 1).year).strftime('%B %Y')}"
			end

			 survival_analysis_outcomes[key] = {
        'Number Alive and on ART' => 0,
        'Number Dead' => 0, 'Number Defaulted' => 0 ,
        'Number Stopped Treatment' => 0, 'Number Transferred out' => 0,
        "Section date range" => "#{range[:start_date].strftime('%B %Y')} to #{range[:end_date].strftime('%B %Y')}",
        'Unknown' => 0,'New patients registered for ART' => states.length}


      patient_state['Transferred out'] = [] if patient_state['Transferred out'].blank?
      patient_state['Stopped taking ARVs'] = [] if patient_state['Stopped taking ARVs'].blank?
      patient_state['Unknown outcomes'] = [] if  patient_state['Unknown outcomes'].blank?
      patient_state['Died total'] = [] if  patient_state['Died total'].blank?
      patient_state['Total alive and on ART'] = [] if patient_state['Total alive and on ART'].blank?
      patient_state['Defaulted'] = [] if patient_state['Defaulted'].blank?
				#raise patient_state['Transferred out'].length.to_yaml
        states.each do | patient_id |
				total << patient_id.to_i
				patient_id = patient_id.to_i
						#raise patient_id.to_yaml if patient_state['Defaulted'].include?(patient_id.patient_id)

         if patient_state['Defaulted'].include?(patient_id)
						defaulted << patient_id
            survival_analysis_outcomes[key]['Number Defaulted']+=1
         elsif patient_state['Transferred out'].include?(patient_id) and !patient_state['Transferred out'].blank?
						transferred << patient_id
            survival_analysis_outcomes[key]['Number Transferred out']+=1
         elsif patient_state['Died total'].include?(patient_id)
						dead << patient_id
            survival_analysis_outcomes[key]['Number Dead']+=1
         elsif patient_state['Stopped taking ARVs'].include?(patient_id)
						stopped << patient_id
            survival_analysis_outcomes[key]['Number Stopped Treatment']+=1
				elsif patient_state['Total alive and on ART'].include?(patient_id)
						arvs << patient_id
            survival_analysis_outcomes[key]['Number Alive and on ART']+=1
      	elsif patient_state['Unknown outcomes'].include?(patient_id)
						unknown << patient_id
            survival_analysis_outcomes[key]['Unknown']+=1
				end
      end
    			views[key] = {

				"total" => total,
				"stopped" => stopped,
				"arvs" => arvs,
				"dead" => dead,
				"transferred" => transferred,
				"defaulted" => defaulted,
				"unknown" => unknown
			}
			#PB - commented out the line below as per request from Support and HIV Unit
			# break if ((i + 1)*12) == 60
		end

    return survival_analysis_outcomes.sort{|a,b| (a[0].to_i == b[0].to_i) ? a[1].to_i <=> b[1].to_i : a[0].to_i <=> b[0].to_i }, views
	end

	def self.childern_survival_analysis(cohort, patient_state)
		self.report(cohort, patient_state, 0, 14)
  end

	def self.pregnant_and_breast_feeding(cohort, patient_state, min_age=nil, max_age=nil)
		sex = "female"
		self.report(cohort, patient_state, min_age, max_age, sex )
	end

end
