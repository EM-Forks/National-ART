class CohortRevise

  @@reason_for_starting = []

  def self.create_temp_earliest_start_date_table(end_date)

    ##########################################################
    ActiveRecord::Base.connection.execute <<EOF
      DROP FUNCTION IF EXISTS patient_date_enrolled;
EOF

    arv_concept_ids = MedicationService.arv_drugs.map(&:concept_id)

    ActiveRecord::Base.connection.execute <<EOF
CREATE FUNCTION patient_date_enrolled(my_patient_id int) RETURNS DATE
DETERMINISTIC
BEGIN
DECLARE my_start_date DATE;
DECLARE min_start_date DATETIME;
DECLARE arv_concept_id INT(11);

SET arv_concept_id = (SELECT concept_id FROM concept_name WHERE name ='ANTIRETROVIRAL DRUGS' LIMIT 1);

SET my_start_date = (SELECT DATE(o.start_date) FROM drug_order d INNER JOIN orders o ON d.order_id = o.order_id AND o.voided = 0 WHERE o.patient_id = my_patient_id AND drug_inventory_id IN(SELECT drug_id FROM drug WHERE concept_id IN(SELECT concept_id FROM concept_set WHERE concept_set = arv_concept_id)) AND d.quantity > 0 AND o.start_date = (SELECT min(start_date) FROM drug_order d INNER JOIN orders o ON d.order_id = o.order_id AND o.voided = 0 WHERE d.quantity > 0 AND o.patient_id = my_patient_id AND drug_inventory_id IN(SELECT drug_id FROM drug WHERE concept_id IN(SELECT concept_id FROM concept_set WHERE concept_set = arv_concept_id))) LIMIT 1);


RETURN my_start_date;
END;
EOF
    ##########################################################




    ActiveRecord::Base.connection.execute <<EOF
      DROP TABLE IF EXISTS `temp_earliest_start_date`;
EOF

    ActiveRecord::Base.connection.execute <<EOF
      CREATE TABLE temp_earliest_start_date
        select
            `p`.`patient_id` AS `patient_id`,
            `pe`.`gender` AS `gender`,
            `pe`.`birthdate`,
            date_antiretrovirals_started(`p`.`patient_id`, min(`s`.`start_date`)) AS `earliest_start_date`,
            cast(patient_date_enrolled(`p`.`patient_id`) as date) AS `date_enrolled`,
            `person`.`death_date` AS `death_date`,
            (select timestampdiff(year, `pe`.`birthdate`, min(`s`.`start_date`))) AS `age_at_initiation`,
            (select timestampdiff(day, `pe`.`birthdate`, min(`s`.`start_date`))) AS `age_in_days`
        from
            ((`patient_program` `p`
            left join `person` `pe` ON ((`pe`.`person_id` = `p`.`patient_id`))
            left join `patient_state` `s` ON ((`p`.`patient_program_id` = `s`.`patient_program_id`)))
            left join `person` ON ((`person`.`person_id` = `p`.`patient_id`)))
        where
            ((`p`.`voided` = 0)
                and (`s`.`voided` = 0)
                and (`p`.`program_id` = 1)
                and (`s`.`state` = 7))
        group by `p`.`patient_id`;
EOF

  end

  def self.get_indicators(start_date, end_date)
    time_started = Time.now().strftime('%Y-%m-%d %H:%M:%S')

#=begin
    self.create_temp_earliest_start_date_table(end_date)
#=end

=begin
    ActiveRecord::Base.connection.execute <<EOF
      CREATE TABLE temp_earliest_start_date
select
        `p`.`patient_id` AS `patient_id`,
        `p`.`gender` AS `gender`,
        `p`.`birthdate`,
        `p`.`earliest_start_date` AS `earliest_start_date`,
         cast(`patient_start_date`(`p`.`patient_id`) as date) AS `date_enrolled`,
        `p`.`death_date` AS `death_date`,
        (select timestampdiff(year, `p`.`birthdate`, `p`.`earliest_start_date`)) AS `age_at_initiation`,
        (select timestampdiff(day, `p`.`birthdate`, `p`.`earliest_start_date`)) AS `age_in_days`
    from
        `patients_on_arvs` `p`
    group by `p`.`patient_id`
EOF

=end



#=end
      #Get earliest date enrolled
      cum_start_date = self.get_cum_start_date

      if cum_start_date.blank?
        cum_start_date = start_date
      end

      cohort = CohortService.new(cum_start_date)

      #Total registered
      cohort.total_registered = self.total_registered(start_date, end_date)
      cohort.cum_total_registered = self.total_registered(cum_start_date, end_date)

      #Patients initiated on ART first time
      cohort.initiated_on_art_first_time = self.initiated_on_art_first_time(start_date, end_date)
      cohort.cum_initiated_on_art_first_time = self.initiated_on_art_first_time(cum_start_date, end_date)

      #Patients re-initiated on ART
      cohort.re_initiated_on_art = self.re_initiated_on_art(start_date, end_date)
      cohort.cum_re_initiated_on_art = self.re_initiated_on_art(cum_start_date, end_date)

      #Patients transferred in on ART
      cohort.transfer_in = self.transfer_in(start_date, end_date)
      cohort.cum_transfer_in = self.transfer_in(cum_start_date, end_date)


      #All males
      cohort.all_males = self.males(start_date, end_date)
      cohort.cum_all_males = self.males(cum_start_date, end_date)

      #Pregnant females (all ages)
=begin
Unique PatientProgram entries at the current location for those patients with at least one state ON ARVs and earliest start date of the 'ON ARVs' state within the quarter and having gender of related PERSON entry as F for female and 'IS PATIENT PREGNANT?' observation answered 'YES' in related HIV CLINIC CONSULTATION encounters within 28 days from earliest registration date OR in HIV Staging encounters
=end
      cohort.pregnant_females_all_ages = self.pregnant_females_all_ages(start_date, end_date)
      cohort.cum_pregnant_females_all_ages = self.pregnant_females_all_ages(cum_start_date, end_date)

      #Non-pregnant females (all ages)
=begin
      Unique PatientProgram entries at the current location for those patients with at least one state ON ARVs
      and earliest start date of the 'ON ARVs' state within the quarter and having gender of
      related PERSON entry as F for female and no entries of 'IS PATIENT PREGNANT?' observation answered 'YES'
      in related HIV CLINIC CONSULTATION encounters not within 28 days from earliest registration date
=end
      cohort.non_pregnant_females = self.non_pregnant_females(start_date, end_date, cohort.pregnant_females_all_ages)
      cohort.cum_non_pregnant_females = self.non_pregnant_females(cum_start_date, end_date, cohort.cum_pregnant_females_all_ages)

      #Children below 24 months at ART initiation
      cohort.children_below_24_months_at_art_initiation = self.children_below_24_months_at_art_initiation(start_date, end_date)
      cohort.cum_children_below_24_months_at_art_initiation = self.children_below_24_months_at_art_initiation(cum_start_date, end_date)

      #Children 24 months – 14 years at ART initiation
      cohort.children_24_months_14_years_at_art_initiation = self.children_24_months_14_years_at_art_initiation(start_date, end_date)
      cohort.cum_children_24_months_14_years_at_art_initiation = self.children_24_months_14_years_at_art_initiation(cum_start_date, end_date)

      #Adults at ART initiation
      cohort.adults_at_art_initiation = self.adults_at_art_initiation(start_date, end_date)
      cohort.cum_adults_at_art_initiation = self.adults_at_art_initiation(cum_start_date, end_date)

      #Unknown age
      cohort.unknown_age = self.unknown_age(start_date, end_date)
      cohort.cum_unknown_age = self.unknown_age(cum_start_date, end_date)

=begin
      The following block - we are calculating all reason for starting for Quarter and Cumulative
=end
      ###########################################################################################
      initiated_reason_on_art_concept = ConceptName.find_by_name('REASON FOR ART ELIGIBILITY').concept

      reason_for_starting = ActiveRecord::Base.connection.select_all <<EOF
      SELECT e.*, patient_reason_for_starting_art(e.patient_id) reason_for_starting_concept_id
      FROM temp_earliest_start_date e
      WHERE e.date_enrolled <= '#{end_date}'
      GROUP BY e.patient_id;
EOF
      (reason_for_starting || []).each do |data|
        @@reason_for_starting << {
          :patient_id => data['patient_id'].to_i,
          :gender => data['gender'], :birthdate => (data['birthdate'].to_date rescue nil),
          :earliest_start_date => (data['earliest_start_date'].to_date rescue nil),
          :date_enrolled => (data['date_enrolled'].to_date rescue '2000-01-01'.to_date),
          :reason_for_starting => data['reason'],
          :age_at_initiation => data['age_at_initiation'].to_i,
          :age_in_days => data['age_in_days'].to_i,
          :reason_for_starting_concept_id => (data['reason_for_starting_concept_id'].to_i rescue nil)
         }
      end
      ###########################################################################################

=begin
      Unique PatientProgram entries at the current location for those patients with at least one state ON ARVs
      and earliest start date of the 'ON ARVs' state within the quarter
      and having a REASON FOR ELIGIBILITY observation with an answer as PRESUMED SEVERE HIV
=end
      cohort.presumed_severe_hiv_disease_in_infants = self.presumed_severe_hiv_disease_in_infants(start_date, end_date)
      cohort.cum_presumed_severe_hiv_disease_in_infants = self.presumed_severe_hiv_disease_in_infants(cum_start_date, end_date)

=begin
      Confirmed HIV infection in infants (PCR)

      Unique PatientProgram entries at the current location for those patients with at least one state ON ARVs
      and earliest start date of the 'ON ARVs' state within the quarter and
      having a REASON FOR ELIGIBILITY observation with an answer as HIV PCR
=end
      cohort.confirmed_hiv_infection_in_infants_pcr = self.confirmed_hiv_infection_in_infants_pcr(start_date, end_date)
      cohort.cum_confirmed_hiv_infection_in_infants_pcr = self.confirmed_hiv_infection_in_infants_pcr(cum_start_date, end_date)

=begin
      WHO stage 1 or 2, CD4 below threshold
      Unique PatientProgram entries at the current location for those patients with at least one state ON ARVs
      and earliest start date of the 'ON ARVs' state within the quarter and having a REASON FOR ELIGIBILITY
      observation with an answer as CD4 COUNT LESS THAN OR EQUAL TO 350 or CD4 COUNT LESS THAN OR EQUAL TO 750
=end
      cohort.who_stage_two = self.who_stage_two(start_date, end_date)
      cohort.cum_who_stage_two = self.who_stage_two(cum_start_date, end_date)

=begin
    Breastfeeding mothers

    Unique PatientProgram entries at the current location for those patients with at least one state
    ON ARVs and earliest start date of the 'ON ARVs' state within the quarter
    and having a REASON FOR ELIGIBILITY observation with an answer as BREASTFEEDING
=end
    cohort.breastfeeding_mothers = self.breastfeeding_mothers(start_date, end_date)
    cohort.cum_breastfeeding_mothers = self.breastfeeding_mothers(cum_start_date, end_date)

=begin
  Pregnant women

  Unique PatientProgram entries at the current location for those patients with at least one state ON ARVs
  and earliest start date of the 'ON ARVs' state within the quarter
  and having a REASON FOR ELIGIBILITY observation with an answer as PATIENT PREGNANT
=end
    cohort.pregnant_women = self.pregnant_women(start_date, end_date)
    cohort.cum_pregnant_women = self.pregnant_women(cum_start_date, end_date)

=begin
  WHO STAGE 3
  Unique PatientProgram entries at the current location for those patients with at least
  one state ON ARVs and earliest start date of the 'ON ARVs' state within the quarter
  and having a REASON FOR ELIGIBILITY observation with an answer as WHO STAGE III
=end
    cohort.who_stage_three = self.who_stage_three(start_date, end_date)
    cohort.cum_who_stage_three = self.who_stage_three(cum_start_date, end_date)

=begin
  WHO STAGE 4
  Unique PatientProgram entries at the current location for those patients with at least
  one state ON ARVs and earliest start date of the 'ON ARVs' state within the quarter
  and having a REASON FOR ELIGIBILITY observation with an answer as WHO STAGE IV
=end
    cohort.who_stage_four = self.who_stage_four(start_date, end_date)
    cohort.cum_who_stage_four = self.who_stage_four(cum_start_date, end_date)

=begin
  Asymptomatic
  Unique PatientProgram entries at the current location for those patients with at least
  one state ON ARVs and earliest start date of the 'ON ARVs' state within the quarter
  and having a REASON FOR ELIGIBILITY observation with an answer as Lymphocytes
  or LYMPHOCYTE COUNT BELOW THRESHOLD WITH WHO STAGE 2

  For all those patients with WHO stage 1 and 2, only those that were enrolled
  after or on 2016-04-01 revised_guidelines_start_date = "2016-04-01"

=end
  cohort.asymptomatic = self.asymptomatic(start_date, end_date)
  cohort.cum_asymptomatic = self.asymptomatic(cum_start_date, end_date)

=begin
    Unknown / other reason outside guidelines
    Unique PatientProgram entries at the current location for those patients with at least one state ON ARVs
    and earliest start date of the 'ON ARVs' state within the quarter
    and having a REASON FOR ELIGIBILITY observation with an answer as UNKNOWN
=end
    cohort.unknown_other_reason_outside_guidelines = self.unknown_other_reason_outside_guidelines(start_date, end_date)
    cohort.cum_unknown_other_reason_outside_guidelines = self.unknown_other_reason_outside_guidelines(cum_start_date, end_date)

=begin
   Children 12-23 months

   Unique PatientProgram entries at the current location for those patients with at least one state
   ON ARVs and earliest start date of the 'ON ARVs' state within the quarter and having
   Confirmed HIV Infection (HIV Rapid antibody test or DNA-PCR), regardless of WHO stage and CD4 Count
=end
    cohort.children_12_23_months = self.children_12_23_months(start_date, end_date)
    cohort.cum_children_12_23_months = self.children_12_23_months(cum_start_date, end_date)

=begin
        Current EPISODE OF TB

        Unique PatientProgram entries at the current location for those patients with at least one state
        ON ARVs and earliest start date of the 'ON ARVs' state within the quarter and having a
        CURRENT EPISODE OF TB observation at the HIV staging encounter on the initiation date
=end

        cohort.current_episode_of_tb = self.current_episode_of_tb(start_date, end_date)
        cohort.cum_current_episode_of_tb = self.current_episode_of_tb(cum_start_date, end_date)

=begin
    TB within the last 2 years

    Unique PatientProgram entries at the current location for those patients with at least one state ON ARVs
    and earliest start date of the 'ON ARVs' state within the quarter
    and having a TB WITHIN THE LAST 2 YEARS observation at the HIV staging encounter on the initiation date
=end
    cohort.tb_within_the_last_two_years = self.tb_within_the_last_two_years(cohort.current_episode_of_tb, start_date, end_date)
    cohort.cum_tb_within_the_last_two_years = self.tb_within_the_last_two_years(cohort.cum_current_episode_of_tb, cum_start_date, end_date)

=begin
    No TB
    total_registered - (current_episode - tb_within_the_last_two_years)
=end
    cohort.no_tb = self.no_tb(cohort.total_registered, cohort.tb_within_the_last_two_years, cohort.current_episode_of_tb)
    cohort.cum_no_tb = self.cum_no_tb(cohort.cum_total_registered, cohort.cum_tb_within_the_last_two_years, cohort.cum_current_episode_of_tb)

=begin
    Kaposis Sarcoma

    Unique PatientProgram entries at the current location for those patients with at least one state ON ARVs
    and earliest start date of the 'ON ARVs' state within the quarter and having a KAPOSIS SARCOMA observation
    at the HIV staging encounter on the initiation date
=end
    cohort.kaposis_sarcoma = self.kaposis_sarcoma(start_date, end_date)
    cohort.cum_kaposis_sarcoma = self.kaposis_sarcoma(cum_start_date, end_date)

=begin
    From this point going down: we update temp_earliest_start_date cum_outcome field to have the latest Cumulative outcome
=end
    self.update_cum_outcome(end_date)


=begin
    Total Alive and On ART
    Unique PatientProgram entries at the current location for those patients with at least one state
    ON ARVs and earliest start date of the 'ON ARVs' state less than or equal to end date of quarter
    and latest state is ON ARVs  (Excluding defaulters)
=end
    cohort.total_alive_and_on_art                      = self.get_outcome('On antiretrovirals')
    cohort.died_within_the_1st_month_of_art_initiation = self.died_in('1st month')
    cohort.died_within_the_2nd_month_of_art_initiation = self.died_in('2nd month')
    cohort.died_within_the_3rd_month_of_art_initiation = self.died_in('3rd month')
    cohort.died_after_the_3rd_month_of_art_initiation  = self.died_in('4+ months')
    cohort.died_total                                  = self.get_outcome('Patient died')
    cohort.defaulted                                   = self.get_outcome('Defaulted')
    cohort.stopped_art                                 = self.get_outcome('Treatment stopped')
    cohort.transfered_out                              = self.get_outcome('Patient transferred out')
    cohort.unknown_outcome                             = self.get_outcome('Pre-ART (Continue)')

=begin
    ARV Regimen category
    Alive and On ART and Value Coded of the latest 'Regimen Category' Observation
    of each patient that is linked to the Dispensing encounter in the reporting period
=end

    @@regimen_categories = self.cal_regimem_category(cohort.total_alive_and_on_art, end_date)

    cohort.zero_a           = self.get_regimen_category('0A')
    cohort.one_a            = self.get_regimen_category('1A')
    cohort.zero_p           = self.get_regimen_category('0P')
    cohort.one_p            = self.get_regimen_category('1P')
    cohort.two_a            = self.get_regimen_category('2A')
    cohort.two_p            = self.get_regimen_category('2P')
    cohort.three_a          = self.get_regimen_category('3A')
    cohort.three_p          = self.get_regimen_category('3P')
    cohort.four_a           = self.get_regimen_category('4A')
    cohort.four_p           = self.get_regimen_category('4P')
    cohort.five_a           = self.get_regimen_category('5A')
    cohort.six_a            = self.get_regimen_category('6A')
    cohort.seven_a          = self.get_regimen_category('7A')
    cohort.eight_a          = self.get_regimen_category('8A')
    cohort.nine_a           = self.get_regimen_category('9A')
    cohort.nine_p           = self.get_regimen_category('9P')
    cohort.ten_a            = self.get_regimen_category('10A')
    cohort.elleven_a        = self.get_regimen_category('11A')
    cohort.elleven_p        = self.get_regimen_category('11P')
    cohort.twelve_a         = self.get_regimen_category('12A')
    cohort.unknown_regimen  = self.get_regimen_category('unknown_regimen')

=begin
    Total patients with side effects:
    Alive and On ART patients with DRUG INDUCED observations during their last HIV CLINIC CONSULTATION encounter up to the reporting period
=end
    cohort.total_patients_with_side_effects = self.total_patients_with_side_effects(cohort, cohort.total_alive_and_on_art, start_date, end_date)
    #cohort.total_patients_without_side_effects = self.total_patients_without_side_effects(cohort.total_alive_and_on_art, cohort.total_patients_with_side_effects)
    #cohort.unknown_side_effects = self.unknown_side_effects(cohort.total_alive_and_on_art, start_date, end_date)


=begin
    TB Status
    Alive and On ART with 'TB Status' observation value of 'TB not Suspected' or 'TB Suspected'
    or 'TB confirmed and on Treatment', or 'TB confirmed and not on Treatment' or 'Unknown TB status'
    during their latest HIV Clinic Consultaiton encounter in the reporting period
=end
    @@tb_status = self.cal_tb_status(cohort.total_alive_and_on_art, end_date)

    cohort.tb_suspected = self.get_tb_status('TB suspected')
    cohort.tb_not_suspected = self.get_tb_status('TB NOT suspected')
    cohort.tb_confirmed_on_tb_treatment = self.get_tb_status('Confirmed TB on treatment')
    cohort.tb_confirmed_currently_not_yet_on_tb_treatment = self.get_tb_status('Confirmed TB NOT on treatment')
    cohort.unknown_tb_status = self.get_tb_status('unknown_tb_status')

=begin
      The following block of code make sure the patients that were screened for TB and
      those not but are on ART should add up to Total Alive and on ART
=end
    #===============================================================================================================
    unknown_tb_status = [] ; unknow_tb_status_patient_ids = []
    (cohort.total_alive_and_on_art || []).each do |row|
    patient_id = row['patient_id'].to_i ; patient_id_found = []

    (cohort.tb_suspected || []).each do |s|
      patient_id_found << s[:patient_id] if s[:patient_id] == patient_id
    end

    (cohort.tb_not_suspected || []).each do |s|
      patient_id_found << s[:patient_id] if s[:patient_id] == patient_id
    end if patient_id_found.blank?

    (cohort.tb_confirmed_on_tb_treatment || []).each do |s|
      patient_id_found << s[:patient_id] if s[:patient_id] == patient_id
    end if patient_id_found.blank?

    (cohort.tb_confirmed_currently_not_yet_on_tb_treatment || []).each do |s|
      patient_id_found << s[:patient_id] if s[:patient_id] == patient_id
    end if patient_id_found.blank?

    (cohort.unknown_tb_status || []).each do |s|
      patient_id_found << s[:patient_id] if s[:patient_id] == patient_id
    end if patient_id_found.blank?

    unknown_tb_status << {:patient_id => patient_id, :tb_status => 'unknown_tb_status' } if patient_id_found.blank?
    end

    cohort.unknown_tb_status = (cohort.unknown_tb_status + unknown_tb_status) unless unknown_tb_status.blank?
    #===============================================================================================================

=begin
  ART adherence

  Alive and On ART with value of their 'Drug order adherence" observation during their latest Adherence
  encounter in the reporting period  between 95 and 105
=end
    adherent, not_adherent, unknown_adherence = self.latest_art_adherence(cohort.total_alive_and_on_art, end_date)
    cohort.patients_with_0_6_doses_missed_at_their_last_visit = adherent
    cohort.patients_with_7_plus_doses_missed_at_their_last_visit = not_adherent
    cohort.patients_with_unknown_adhrence = unknown_adherence

=begin
  Pregnant and breastfeeding status during Consultaiton
=end
    cohort.total_pregnant_women = self.total_pregnant_women(cohort.total_alive_and_on_art, start_date, end_date)
    cohort.total_breastfeeding_women = self.total_breastfeeding_women(cohort.total_alive_and_on_art, start_date, end_date)
    cohort.total_other_patients = self.total_other_patients(cohort.total_alive_and_on_art, cohort.total_breastfeeding_women, cohort.total_pregnant_women)

=begin
    Patients with CPT dispensed at least once before end of quarter and on ARVs
=end
    cohort.total_patients_on_arvs_and_cpt = self.total_patients_on_arvs_and_cpt(cohort.total_alive_and_on_art, start_date, end_date)

=begin
    Patients with IPT dispensed at least once before end of quarter and on ARVS
=end
    cohort.total_patients_on_arvs_and_ipt = self.total_patients_on_arvs_and_ipt(cohort.total_alive_and_on_art,  start_date, end_date)

=begin
    Patients on family planning methods at least once before end of quarter and on ARVs
=end
    cohort.total_patients_on_family_planning = self.total_patients_on_family_planning(cohort.total_alive_and_on_art, start_date, end_date)

=begin
    Patients whose BP was screened and are above 30 years least once before end of quarter and on ARVs
=end
    cohort.total_patients_with_screened_bp = self.total_patients_with_screened_bp(cohort.total_alive_and_on_art, start_date, end_date)

    puts "Started at: #{time_started}. Finished at: #{Time.now().strftime('%Y-%m-%d %H:%M:%S')}"
    return cohort

  end

  def self.get_disaggregated_cohort(start_date, end_date, gender, ag)
    if ag == '50+ years'
      diff = [50, 1000]
      iu = 'year'
    elsif ag.match(/years/i)
      diff = ag.sub(' years','').split('-')
      iu = 'year'
    elsif ag.match(/months/i)
      diff = ag.sub(' months','').split('-')
      iu = 'month'
    else
      if gender == 'M'
        diff = [0, 1000]
        iu = 'year' ; gender = 'M'
      elsif gender == 'FNP'
        diff = [0, 1000]
        iu = 'year' ; gender = 'F'
      elsif gender == 'FP'
        diff = [0, 1000]
        iu = 'year' ; gender = 'F'
      elsif gender == 'FBf'
        diff = [0, 1000]
        iu = 'year' ; gender = 'F'
      end
    end

    data = ActiveRecord::Base.connection.select_all <<EOF
    SELECT patient_id  FROM temp_earliest_start_date
    WHERE earliest_start_date BETWEEN '#{start_date.to_date}' AND '#{end_date.to_date}'
    AND (earliest_start_date) = (date_enrolled) AND gender = '#{gender.first}'
    AND timestampdiff(#{iu}, birthdate, date_enrolled) BETWEEN #{diff[0].to_i} AND #{diff[1].to_i};
EOF

    data1 = ActiveRecord::Base.connection.select_all <<EOF
    SELECT t1.patient_id FROM temp_earliest_start_date t1
    INNER JOIN temp_patient_outcomes t2 ON t1.patient_id = t2.patient_id
    WHERE date_enrolled <= '#{end_date.to_date}' AND gender = '#{gender.first}'
    AND cum_outcome = 'On antiretrovirals'
    AND timestampdiff(#{iu}, birthdate, date_enrolled) BETWEEN #{diff[0].to_i} AND #{diff[1].to_i};
EOF

=begin
    data2 = ActiveRecord::Base.connection.select_one <<EOF
    SELECT count(*) as started FROM temp_earliest_start_date
    WHERE earliest_start_date BETWEEN '#{start_date.to_date}' AND '#{end_date.to_date}'
    AND (earliest_start_date) = (date_enrolled) AND gender = '#{gender.first}';
EOF
=end

    dispensing_encounter_id = EncounterType.find_by_name('DISPENSING').id
    amount_dispensed = ConceptName.find_by_name('Amount dispensed').concept_id
    ipt_drug_ids = Drug.find_all_by_concept_id(656).map(&:drug_id)

    patient_ids = []
    (data1 || {}).each do |x, y|
      patient_ids << x['patient_id'].to_i
    end

    unless patient_ids.blank?
    data2 = ActiveRecord::Base.connection.select_all <<EOF
      SELECT e.patient_id FROM encounter e
      INNER JOIN temp_patient_outcomes o ON o.patient_id = e.patient_id
      AND o.cum_outcome = 'On antiretrovirals' INNER JOIN obs ON obs.encounter_id = e.encounter_id
      AND obs.concept_id = #{amount_dispensed}
      WHERE value_drug IN(#{ipt_drug_ids.join(',')})
      AND e.patient_id IN(#{patient_ids.join(',')})
      AND encounter_datetime BETWEEN '#{start_date.to_date.strftime('%Y-%m-%d 00:00:00')}'
      AND '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}' GROUP BY e.patient_id;
EOF

    end

=begin
    data3 = ActiveRecord::Base.connection.select_all <<EOF
      SELECT e.patient_id FROM encounter e
      INNER JOIN temp_patient_outcomes o ON o.patient_id = e.patient_id
      AND o.cum_outcome = 'On antiretrovirals' INNER JOIN obs ON obs.encounter_id = e.encounter_id
      AND obs.concept_id = #{amount_dispensed}
      WHERE value_drug IN(#{ipt_drug_ids.join(',')})
      AND e.patient_id IN(#{patient_ids.join(',')})
      AND encounter_datetime BETWEEN '#{start_date.to_date.strftime('%Y-%m-%d 00:00:00')}'
      AND '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}' GROUP BY e.patient_id;
EOF
=end

    return [
      (data.length rescue 0),
      (data1.length rescue 0),
      (data2.length rescue 0),
       0]
  end

  def self.patient_with_missing_start_reasons(start_date, end_date)
    begin
      patients = ActiveRecord::Base.connection.select_all <<EOF
      SELECT e.*, patient_reason_for_starting_art_text(e.patient_id) reason FROM temp_earliest_start_date e
      WHERE date_enrolled BETWEEN '#{start_date.to_date}' AND '#{end_date.to_date}';
EOF

      data = {}
      (patients || []).each do |p|
        patient = Patient.find(p['patient_id'].to_i)
        reason_for_starting = p['reason']
        next unless reason_for_starting.blank?

        patient_outcome = ActiveRecord::Base.connection.select_one <<EOF
            SELECT patient_outcome(#{patient.patient_id}, DATE('#{end_date.to_date}')) AS outcome;
EOF

        patient_obj = PatientService.get_patient(patient.person)
        data[patient_obj.patient_id] = {
          :arv_number => patient_obj.arv_number,
          :earliest_start_date => (p['earliest_start_date'].to_date rescue nil),
          :date_enrolled => (p['date_enrolled'].to_date rescue nil),
          :name => patient_obj.name,
          :gender => patient_obj.sex,
          :birthdate => patient_obj.birth_date,
          :outcome => patient_outcome['outcome']
        }
      end

      return data
    rescue
      raise "Try running the revised cohort before this report"
    end
  end

  def self.on_art_patients_with_no_arvs_dispensations(start_date, end_date)
    arv_drugs = MedicationService.arv_drugs
    arv_drugs = arv_drugs.map{ |d| d.concept_id }

    start_date = start_date.to_date ; end_date = end_date.to_date

    data = ActiveRecord::Base.connection.select_all <<EOF
    SELECT patient_id FROM orders o
    INNER JOIN drug_order drg ON drg.order_id = o.order_id
    AND o.voided = 0
    WHERE drug_inventory_id IN(
      SELECT drug_id FROM drug
      WHERE concept_id IN(#{arv_drugs.join(',')})

    ) GROUP BY patient_id;

EOF

    patient_ids = data.map{ |d| d['patient_id'].to_i  }

    begin
      patients = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date
      WHERE patient_id NOT IN(#{patient_ids.join(',')});
EOF

    rescue
      raise "Try running the revised cohort before this report"
    end

    reason_for_starting = ConceptName.find_by_name('REASON FOR ART ELIGIBILITY').concept
    data = {}

    (patients || []).each do |p|
      patient = Patient.find(p['patient_id'].to_i)
      reason_for_starting = PatientService.reason_for_art_eligibility(patient)
      #next unless reason_for_starting.blank?

      patient_outcome = ActiveRecord::Base.connection.select_one <<EOF
          SELECT patient_outcome(#{patient.patient_id}, DATE('#{end_date.to_date}')) AS outcome;
EOF

      patient_obj = PatientService.get_patient(patient.person)
      data[patient_obj.patient_id] = {
        :arv_number => patient_obj.arv_number,
        :earliest_start_date => (p['earliest_start_date'].to_date rescue nil),
        :date_enrolled => (p['date_enrolled'].to_date rescue nil),
        :name => patient_obj.name,
        :gender => patient_obj.sex,
        :birthdate => patient_obj.birth_date,
        :outcome => patient_outcome['outcome']
      }
    end

    return data
  end

  def self.patient_on_pre_ART_but_have_arvs_dispensed(start_date, end_date)

    begin
      patients = ActiveRecord::Base.connection.select_all <<EOF
      SELECT e.* FROM temp_earliest_start_date e
      INNER JOIN temp_patient_outcomes o ON e.patient_id = o.patient_id
      WHERE date_enrolled BETWEEN '#{start_date.to_date}' AND '#{end_date.to_date}'
      AND cum_outcome LIKE '%Pre-%';
EOF

    rescue
      raise "Try running the revised cohort before this report"
    end


    data = {}

    (patients || []).each do |p|
      patient = Patient.find(p['patient_id'].to_i)
      reason_for_starting = PatientService.reason_for_art_eligibility(patient)
      #next unless reason_for_starting.blank?

      patient_outcome = ActiveRecord::Base.connection.select_one <<EOF
          SELECT patient_outcome(#{patient.patient_id}, DATE('#{end_date.to_date}')) AS outcome;
EOF

      patient_obj = PatientService.get_patient(patient.person)
      data[patient_obj.patient_id] = {
        :arv_number => patient_obj.arv_number,
        :earliest_start_date => (p['earliest_start_date'].to_date rescue nil),
        :date_enrolled => (p['date_enrolled'].to_date rescue nil),
        :name => patient_obj.name,
        :gender => patient_obj.sex,
        :birthdate => patient_obj.birth_date,
        :outcome => patient_outcome['outcome']
      }
    end

    return data
  end

  def self.patients_with_pre_art_or_unknown_outcome(start_date, end_date)

    begin
      patients = ActiveRecord::Base.connection.select_all <<EOF
      SELECT e.*, cum_outcome, patient_reason_for_starting_art_text(e.patient_id) reason_for_starting
      FROM temp_patient_outcomes o
      INNER JOIN temp_earliest_start_date e ON e.patient_id = o.patient_id
      WHERE cum_outcome LIKE '%Pre-%' OR cum_outcome LIKE '%Unknown%';
EOF

    rescue
      raise "Try running the revised cohort before this report"
    end

    data = {}

    (patients || []).each do |p|
      patient = Patient.find(p['patient_id'].to_i)

      patient_outcome = p['cum_outcome']
      person = Person.find(p['patient_id'])

      patient_obj = PatientService.get_patient(person)
      data[patient_obj.patient_id] = {
        :arv_number => patient_obj.arv_number,
        :earliest_start_date => (p['earliest_start_date'].to_date rescue nil),
        :date_enrolled => (p['date_enrolled'].to_date rescue nil),
        :name => patient_obj.name,
        :gender => patient_obj.sex,
        :birthdate => patient_obj.birth_date,
        :reason_for_starting => p['reason_for_starting'],
        :outcome => patient_outcome['outcome']
      }
    end

    return data
  end

  def self.missing_arv_dispensions(start_date, end_date)
    begin
      patients = ActiveRecord::Base.connection.select_all <<EOF
      SELECT e.*, patient_reason_for_starting_art_text(e.patient_id) reason_for_starting
      FROM temp_earliest_start_date e
      WHERE (date_enrolled IS NULL OR LENGTH(date_enrolled) < 1);
EOF

    rescue
      raise "Try running the revised cohort before this report"
    end

    data = {}

    (patients || []).each do |p|
      patient = Patient.find(p['patient_id'].to_i)

      patient_outcome = ActiveRecord::Base.connection.select_one <<EOF
          SELECT patient_outcome(#{patient.patient_id}, DATE('#{end_date.to_date}')) AS outcome;
EOF

      patient_obj = PatientService.get_patient(patient.person)
      data[patient_obj.patient_id] = {
        :arv_number => patient_obj.arv_number,
        :earliest_start_date => (p['earliest_start_date'].to_date rescue nil),
        :date_enrolled => (p['date_enrolled'].to_date rescue nil),
        :name => patient_obj.name,
        :gender => patient_obj.sex,
        :reason_for_starting => p['reason_for_starting'],
        :birthdate => patient_obj.birth_date,
        :outcome => patient_outcome['outcome']
      }
    end

    return data
  end

  private

  def self.total_patients_with_screened_bp(patients_list, start_date, end_date)
    patient_ids = []
    (patients_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?
    result = []

    systolic_blood_presssure_concept_id = ConceptName.find_by_name("Systolic blood pressure").concept_id
    diastolic_pressure_concept_id = ConceptName.find_by_name("Diastolic blood pressure").concept_id

    results = ActiveRecord::Base.connection.select_all <<EOF
      SELECT o.person_id
      FROM obs o
      WHERE o.voided = 0 AND (o.concept_id in (#{systolic_blood_presssure_concept_id}, #{diastolic_pressure_concept_id}) AND o.value_text IS NOT NULL)
      AND o.person_id IN (#{patient_ids.join(',')})
      AND o.obs_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      AND DATE(o.obs_datetime) = (SELECT max(date(obs.obs_datetime)) FROM obs obs
                                  WHERE obs.voided = 0
                    							AND (obs.concept_id IN (#{systolic_blood_presssure_concept_id}, #{diastolic_pressure_concept_id}) AND obs.value_text IS NOT NULL)
                    							AND obs.obs_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
                                  AND obs.person_id = o.person_id)
      GROUP BY o.person_id;
EOF

    total_percent = (((results.count).to_f / (patient_ids.count).to_f) * 100).to_i
    return total_percent
  end

  def self.total_patients_on_family_planning(patients_list, start_date, end_date)

    patient_ids = []; patient_list = []

    (patients_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?
    result = []

    all_women = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date
      WHERE (gender = 'F' OR gender = 'Female') AND patient_id IN  (#{patient_ids.join(',')})
      AND date_enrolled BETWEEN '#{start_date.to_date}' AND '#{end_date.to_date}'
      GROUP BY patient_id;
EOF

    (all_women || []).each do |patient|
        patient_list << patient['patient_id'].to_i
    end
    
    return 0 if patient_list.blank?

    hiv_clinic_consultation_encounter_type_id = EncounterType.find_by_name('HIV CLINIC CONSULTATION').encounter_type_id
    method_of_family_planning_concept_id = ConceptName.find_by_name("Method of family planning").concept_id
    family_planning_action_to_take_concept_id = ConceptName.find_by_name("Family planning, action to take").concept_id
    none_concept_id = [ConceptName.find_by_name("None").concept_id, ConceptName.find_by_name("No").concept_id]

    results = ActiveRecord::Base.connection.select_all <<EOF
      SELECT o.person_id
      FROM obs o
       inner join encounter e on e.encounter_id = o.encounter_id AND e.encounter_type = #{hiv_clinic_consultation_encounter_type_id}
      WHERE o.voided = 0 AND e.voided = 0
      AND (o.concept_id IN (#{family_planning_action_to_take_concept_id}, #{method_of_family_planning_concept_id}) AND o.value_coded NOT IN (#{none_concept_id.join(',')}))
      AND o.person_id IN (#{patient_list.join(',')})
      AND o.obs_datetime BETWEEN '#{start_date.to_date.strftime('%Y-%m-%d 00:00:00')}' 
      AND '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      AND DATE(o.obs_datetime) = (SELECT max(date(obs.obs_datetime)) FROM obs obs
        WHERE obs.voided = 0
        AND (obs.concept_id IN (#{family_planning_action_to_take_concept_id}, #{method_of_family_planning_concept_id}))
        AND obs.obs_datetime BETWEEN '#{start_date.to_date.strftime('%Y-%m-%d 00:00:00')}' 
        AND '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
        AND obs.person_id = o.person_id)
      GROUP BY o.person_id;
EOF

    total_percent = (((results.count).to_f / (patient_list.count).to_f) * 100).to_i rescue 0
    return total_percent
  end

  def self.total_patients_on_arvs_and_ipt(patients_list, start_date, end_date)
    isoniazid_concept_id = ConceptName.find_by_name("Isoniazid").concept_id
    pyridoxine_concept_id = ConceptName.find_by_name("Pyridoxine").concept_id

    patient_ids = []
    (patients_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?
    result = []

    results = ActiveRecord::Base.connection.select_all <<EOF
      SELECT ods.patient_id FROM orders ods
       INNER JOIN drug_order dos ON ods.order_id = dos.order_id AND ods.voided = 0
      WHERE ods.concept_id IN (#{isoniazid_concept_id}, #{pyridoxine_concept_id})
      AND dos.quantity IS NOT NULL
      AND ods.patient_id in (#{patient_ids.join(',')})
      AND ods.start_date BETWEEN '#{start_date.to_date.strftime('%Y-%m-%d 00:00:00')}' 
      AND '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      AND DATE(ods.start_date) = (SELECT MAX(DATE(o.start_date)) FROM orders o
                    							 INNER JOIN drug_order d ON o.order_id = d.order_id AND o.voided = 0
                    							WHERE o.concept_id IN (#{isoniazid_concept_id}, #{pyridoxine_concept_id})
                                  AND o.patient_id = ods.patient_id
                                  AND d.quantity IS NOT NULL
                                  AND o.start_date BETWEEN '#{start_date.to_date.strftime('%Y-%m-%d 00:00:00')}' 
                                  AND '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}')

      GROUP BY ods.patient_id;
EOF

    total_percent = (((results.count).to_f / (patient_ids.count).to_f) * 100).to_i
    return total_percent
  end

  def self.total_patients_on_arvs_and_cpt(patients_list, start_date, end_date)
    cpt_concept_id = ConceptName.find_by_name("Cotrimoxazole").concept_id

    patient_ids = []
    (patients_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?
    result = []

    results = ActiveRecord::Base.connection.select_all <<EOF
      SELECT ods.patient_id FROM orders ods
       INNER JOIN drug_order dos ON ods.order_id = dos.order_id AND ods.voided = 0
      WHERE ods.concept_id = #{cpt_concept_id}
      AND dos.quantity IS NOT NULL
      AND ods.patient_id in (#{patient_ids.join(',')})
      AND ods.start_date BETWEEN '#{start_date.to_date.strftime('%Y-%m-%d 00:00:00')}' 
      AND '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      AND DATE(ods.start_date) = (SELECT MAX(DATE(o.start_date)) FROM orders o
                    							 INNER JOIN drug_order d ON o.order_id = d.order_id AND o.voided = 0
                    							WHERE o.concept_id =  #{cpt_concept_id}
                                  AND d.quantity IS NOT NULL
                                  AND o.patient_id = ods.patient_id
                                  AND o.start_date BETWEEN '#{start_date.to_date.strftime('%Y-%m-%d 00:00:00')}' 
                                  AND '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}')

      GROUP BY ods.patient_id;
EOF
    total_percent = (((results.count).to_f / (patient_ids.count).to_f) * 100).to_i
    return total_percent
  end

  def self.total_breastfeeding_women(patients_list, start_date, end_date)
    patient_ids = []
    (patients_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?
    result = []

    total_pregnant_females = []
    (total_pregnant_women(patients_list, start_date, end_date) || []).each do |person|
      total_pregnant_females << person['person_id'].to_i
    end

    total_pregnant_females = [0] if total_pregnant_females.blank?

    hiv_clinic_consultation_encounter_type_id = EncounterType.find_by_name('HIV CLINIC CONSULTATION').encounter_type_id
    breastfeeding_concept_id = ConceptName.find_by_name("Breast feeding?").concept_id

    results = ActiveRecord::Base.connection.select_all <<EOF
      SELECT person_id  FROM obs obs
        INNER JOIN encounter enc ON enc.encounter_id = obs.encounter_id AND enc.voided = 0
      WHERE obs.person_id IN (#{patient_ids.join(',')})
      AND obs.person_id NOT IN (#{total_pregnant_females.join(',')})
      AND obs.obs_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}' AND obs.concept_id = #{breastfeeding_concept_id} AND obs.value_coded = 1065
      AND obs.voided = 0 AND enc.encounter_type = #{hiv_clinic_consultation_encounter_type_id}
      AND DATE(obs.obs_datetime) = (SELECT MAX(DATE(o.obs_datetime)) FROM obs o
      							WHERE o.concept_id = #{breastfeeding_concept_id} AND voided = 0
      							AND o.person_id = obs.person_id AND o.obs_datetime <='#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}')
      GROUP BY obs.person_id;
EOF

    return results
  end

  def self.total_pregnant_women(patients_list, start_date, end_date)
    patient_ids = []
    (patients_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?
    result = []

    hiv_clinic_consultation_encounter_type_id = EncounterType.find_by_name('HIV CLINIC CONSULTATION').encounter_type_id
    pregnant_concept_id = ConceptName.find_by_name("Is patient pregnant?").concept_id

    results = ActiveRecord::Base.connection.select_all <<EOF
      SELECT person_id FROM obs obs
        INNER JOIN encounter enc ON enc.encounter_id = obs.encounter_id AND enc.voided = 0
      WHERE obs.person_id IN (#{patient_ids.join(',')})
      AND obs.obs_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}' AND obs.concept_id = #{pregnant_concept_id} AND obs.value_coded = '1065'
      AND obs.voided = 0 AND enc.encounter_type = #{hiv_clinic_consultation_encounter_type_id}
      AND DATE(obs.obs_datetime) = (SELECT MAX(DATE(o.obs_datetime)) FROM obs o
                    WHERE o.concept_id = #{pregnant_concept_id} AND voided = 0
                    AND o.person_id = obs.person_id AND o.obs_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}')
      GROUP BY obs.person_id;
EOF
    return results
  end

  def self.total_other_patients(patient_list, all_breastfeeding_women, all_pregnant_women)
    patient_ids = []; all_pregnant_women_ids = []; all_breastfeeding_women_ids = []

    (patient_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    (all_pregnant_women || []).each do |row|
      all_pregnant_women_ids << row['person_id'].to_i
    end

    (all_breastfeeding_women || []).each do |row|
      all_breastfeeding_women_ids << row['person_id'].to_i
    end

    results = (patient_ids - (all_breastfeeding_women_ids + all_pregnant_women_ids))
    return results
  end

  def self.latest_art_adherence(patient_list, end_date)
    patient_ids = []

    (patient_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end
    return [[], [], []] if patient_ids.blank?

    adherence = ActiveRecord::Base.connection.select_all <<EOF
      SELECT person_id, value_numeric, value_text FROM obs t WHERE concept_id = 6987 AND voided = 0
      AND obs_datetime BETWEEN (SELECT CONCAT(date(max(obs_datetime)),' 00:00:00') FROM obs
        WHERE concept_id = 6987 AND voided = 0 AND person_id = t.person_id
        AND obs_datetime <= '#{end_date} 23:59:59'
      ) AND (SELECT CONCAT(date(max(obs_datetime)),' 23:59:59') FROM obs
        WHERE concept_id = 6987 AND voided = 0 AND person_id = t.person_id
        AND obs_datetime <= '#{end_date} 23:59:59'
      ) AND person_id IN (#{patient_ids.join(',')})
      AND obs_datetime <= '#{end_date} 23:59:59';
EOF

    adherent = [] ; not_adherent = [] ; unknown_adherence = [];

    (adherence || []).each do |ad|
      if ad['value_text'].match(/unknown/i)
        unknown_adherence << ad['person_id'].to_i ; unknown_adherence = unknown_adherence.uniq
        next
      end unless ad['value_text'].blank?

      rate = ad['value_text'].to_f unless ad['value_text'].blank?
      rate = ad['value_numeric'].to_f unless ad['value_numeric'].blank?
      rate = 0 if rate.blank?

      if rate >= 95
        adherent << ad['person_id'].to_i ; adherent = adherent.uniq
      elsif rate < 95
        not_adherent << ad['person_id'].to_i ; not_adherent = not_adherent.uniq
      end
    end

    found_in_both = (adherent & not_adherent)
    found_in_both = [] if found_in_both.blank?

    adherent = (adherent - found_in_both)
    new_patients_with_no_adherence_done = (patient_ids.uniq - (adherent + not_adherent))
    unknown_adherence = (new_patients_with_no_adherence_done + unknown_adherence).uniq

    return [adherent, not_adherent.uniq, unknown_adherence]
  end

  def self.unknown_side_effects(data, start_date, end_date)
    patient_ids = []
    (data || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?
    result = []

  	drug_induced_concept_id = ConceptName.find_by_name('Drug induced').concept_id
    malawi_art_side_effects_concept_id = ConceptName.find_by_name('Malawi ART side effects').concept_id
    unknown_side_effects_concept_id = ConceptName.find_by_name('Unknown').concept_id

    malawi_art_side_effects =  ActiveRecord::Base.connection.select_all <<EOF
            SELECT * FROM obs o WHERE o.voided = 0 AND o.concept_id IN (#{malawi_art_side_effects_concept_id}, #{drug_induced_concept_id} )
            AND o.value_coded = #{unknown_side_effects_concept_id}
            AND (o.person_id IN (#{patient_ids.join(',')}))
            AND o.obs_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
            AND o.obs_datetime = (
              SELECT min(obs_datetime) FROM obs WHERE concept_id IN (#{malawi_art_side_effects_concept_id}, #{drug_induced_concept_id})
              AND voided = 0 AND person_id = o.person_id
              AND obs_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
            ) GROUP BY person_id
EOF

    (malawi_art_side_effects || []).each do |row|
      result << row
    end
    return result
  end

  def self.cal_tb_status(patient_list, end_date)
    patient_ids = []
    tb_status = []

    (patient_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?

    tb_status_concept_id = ConceptName.find_by_name('TB STATUS').concept_id

    data = ActiveRecord::Base.connection.select_all <<EOF
      SELECT person_id, value_coded, value_coded_name_id,  cn.name as tb_status
      FROM obs o
       LEFT JOIN concept_name cn ON o.value_coded = cn.concept_id AND cn.concept_name_type = 'FULLY_SPECIFIED'
      WHERE o.voided = 0 AND o.concept_id = #{tb_status_concept_id}
      AND o.person_id IN(#{patient_ids.join(',')}) AND
      o.obs_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      AND o.obs_datetime = (
        SELECT max(obs_datetime) FROM obs WHERE concept_id = #{tb_status_concept_id}
        AND voided = 0 AND person_id = o.person_id AND
        obs_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
      ) GROUP BY person_id
EOF

    (data || []).each do |patient_tb_status|
      status = patient_tb_status['tb_status']
      status = 'unknown_tb_status' if status.blank?
      tb_status << {
        :patient_id => patient_tb_status['person_id'].to_i,
        :tb_status => status
      }
    end
    return tb_status
  end

  def self.get_tb_status(tb_status)
    registered = []
      (@@tb_status || []).each do |status|
        if tb_status == status[:tb_status]
          registered << {:patient_id => status[:patient_id], :tb_status => status[:tb_status]}
        end
      end

      return registered
  end

  def self.total_patients_with_side_effects(cohort, patients_alive_and_on_art, start_date, end_date)
    patient_ids = []; patients_with_unknown_side_effects = []; results = []
    patient_id_of_those_without_side_effects = []

    (patients_alive_and_on_art || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?

  	drug_induced_concept_id = ConceptName.find_by_name('Drug induced').concept_id
    malawi_art_side_effects_concept_id = ConceptName.find_by_name('Malawi ART side effects').concept_id
    no_side_effects_concept_id = ConceptName.find_by_name('No').concept_id
    yes_side_effects_concept_id = ConceptName.find_by_name('Yes').concept_id
    encounter_type = EncounterType.find_by_name("HIV clinic consultation").encounter_type_id

    malawi_side_effects_ids =  ActiveRecord::Base.connection.select_all <<EOF
    SELECT patient_id, date_enrolled, t1.obs_id, value_coded,
    e.earliest_start_date, t1.obs_datetime
    FROM temp_earliest_start_date e
    INNER JOIN obs t1 ON e.patient_id = t1.person_id
    where t1.person_id IN(#{patient_ids.join(',')})
    AND DATE(t1.obs_datetime) = (SELECT DATE(MAX(encounter_datetime)) FROM encounter e WHERE
    e.encounter_type = #{encounter_type} AND e.patient_id = t1.person_id AND e.voided = 0
    AND e.encounter_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}')
    AND t1.voided = 0 AND concept_id IN(#{malawi_art_side_effects_concept_id}, #{drug_induced_concept_id})
    AND t1.obs_datetime = (SELECT max(obs_datetime) FROM obs t2
    WHERE t2.voided = 0 AND t2.person_id = t1.person_id
    AND t2.concept_id IN(#{malawi_art_side_effects_concept_id}, #{drug_induced_concept_id})
    AND t2.obs_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
    ) GROUP BY t1.person_id, t1.value_coded
    HAVING DATE(obs_datetime) != DATE(earliest_start_date);
EOF

    patient_id_of_those_with_side_effects = []
    patient_id_of_those_without_side_effects = []

    (malawi_side_effects_ids || []).each do |row|
      obs_group = Observation.where(
        ["concept_id = ? AND obs_group_id = ?",
          row['value_coded'].to_i, row['obs_id'].to_i]).first rescue nil

      if obs_group.blank?
        unless patient_id_of_those_with_side_effects.include?(row['patient_id'].to_i)
          next if no_side_effects_concept_id == row['value_coded'].to_i
          results << row
          patient_id_of_those_with_side_effects << row['patient_id'].to_i
        end
      elsif obs_group.value_coded == yes_side_effects_concept_id
        unless patient_id_of_those_with_side_effects.include?(row['patient_id'].to_i)
          results << row
          patient_id_of_those_with_side_effects << row['patient_id'].to_i
        end
      end
    end

    (patient_ids || []).each do |id|
      next if patient_id_of_those_with_side_effects.include?(id)
      patient_id_of_those_without_side_effects << id
    end

    patient_id_of_those_with_unknown_side_effects = (patient_ids) -\
 (patient_id_of_those_with_side_effects + patient_id_of_those_without_side_effects)

    cohort.total_patients_without_side_effects = patient_id_of_those_without_side_effects
    cohort.unknown_side_effects = patient_id_of_those_with_unknown_side_effects

    return results
  end

  def self.total_patients_without_side_effects(patients_alive_and_or_art, patients_with_side_effects)
    patient_ids = []; drug_induced_ids = []; with_side_effects = []; result = []

    (patients_alive_and_or_art || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    #get all patients with side effects
    (patients_with_side_effects || []).each do |row|
      with_side_effects << row['patient_id'].to_i
    end

    #get all patients with unknown_side_effects
    result = patient_ids - with_side_effects
    return result
  end

  def self.cal_regimem_category(patient_list, end_date)
    regimens = []

    patient_ids = []

    (patient_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?

    dispensing_encounter_id = EncounterType.find_by_name("DISPENSING").id
    regimen_category = ConceptName.find_by_name("REGIMEN CATEGORY").concept_id
    regimem_given_concept = ConceptName.find_by_name('ARV REGIMENS RECEIVED ABSTRACTED CONSTRUCT').concept_id
    unknown_regimen_given = ConceptName.find_by_name('UNKNOWN ANTIRETROVIRAL DRUG').concept_id

    data = ActiveRecord::Base.connection.select_all <<EOF
      SELECT e.patient_id, patient_current_regimen(e.patient_id, DATE('#{end_date.to_date}')) regimen_category
      FROM temp_earliest_start_date e
      WHERE patient_id IN(#{patient_ids.join(',')})
      GROUP BY e.patient_id;
EOF

    current_cohort_regimens = [
      "0P", "2P","4P","9P","11P","0A","2A","4A",
      "5A","6A","7A","8A","9A","10A","11A","12A"
    ]

    (data || []).each do |regimen_attr|
        regimen = regimen_attr['regimen_category']

        if regimen.blank? or regimen == 'Unknown' or not current_cohort_regimens.include?(regimen)
          regimen = 'unknown_regimen'
        end

        regimens << {
          :patient_id => regimen_attr['patient_id'].to_i,
          :regimen_category => regimen
        }
      end
      return regimens
  end

  def self.get_regimen_category(arv_regimen_category)
    registered = []
      (@@regimen_categories || []).each do |regimen_attr|
        if arv_regimen_category == regimen_attr[:regimen_category]
          registered << {:patient_id => regimen_attr[:patient_id], :regimen => regimen_attr[:regimen_category]}
        end
      end

      return registered
  end

  def self.died_in(month_str)
    registered = []
    if month_str == "4+ months"
      data = ActiveRecord::Base.connection.select_all <<EOF
        SELECT patient_id, died_in(t.patient_id, cum_outcome, date_enrolled) died_in FROM temp_patient_outcomes o
        INNER JOIN temp_earliest_start_date t USING(patient_id)
        WHERE cum_outcome = 'Patient died' GROUP BY patient_id
        HAVING died_in IN ('4+ months', 'Unknown');
EOF
    else
      data = ActiveRecord::Base.connection.select_all <<EOF
        SELECT patient_id, died_in(t.patient_id, cum_outcome, date_enrolled) died_in FROM temp_patient_outcomes o
        INNER JOIN temp_earliest_start_date t USING(patient_id)
        WHERE cum_outcome = 'Patient died' GROUP BY patient_id
        HAVING died_in = '#{month_str}';
EOF
    end


    (data || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.get_outcome(outcome)
    registered = []

    if outcome == 'Pre-ART (Continue)'
      sql_patch = "cum_outcome = '#{outcome}' OR cum_outcome = 'Unknown'"
    else
      sql_patch = "cum_outcome = '#{outcome}'"
    end

    total_alive_and_on_art = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_patient_outcomes
      WHERE #{sql_patch} GROUP BY patient_id;
EOF
    (total_alive_and_on_art || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.update_cum_outcome(end_date)

      ActiveRecord::Base.connection.execute (
        "DROP TABLE IF EXISTS `temp_patient_outcomes`"
      )

      ActiveRecord::Base.connection.execute(
        "CREATE TABLE temp_patient_outcomes
          SELECT e.patient_id, patient_outcome(e.patient_id, '#{end_date} 23:59:59') AS cum_outcome
        FROM temp_earliest_start_date e WHERE e.date_enrolled <= '#{end_date}'")

  end

  def self.kaposis_sarcoma(start_date, end_date)
    #KAPOSIS SARCOMA
    concept_id = ConceptName.find_by_name('KAPOSIS SARCOMA').concept_id
    yes_concept_id = ConceptName.find_by_name('Yes').concept_id
    who_stages_criteria = ConceptName.find_by_name('Who stages criteria present').concept_id
    registered = []

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date t
      INNER JOIN obs ON t.patient_id = obs.person_id
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND ((value_coded = #{concept_id} AND concept_id = #{who_stages_criteria})
      OR (concept_id = #{concept_id}) AND value_coded = #{yes_concept_id} )
      AND voided = 0 AND DATE(obs_datetime) <= DATE(date_enrolled) GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.current_episode_of_tb(start_date, end_date)
    #CURRENT EPISODE OF TB
    eptb_concept_id = ConceptName.find_by_name('EXTRAPULMONARY TUBERCULOSIS (EPTB)').concept_id
    yes_concept_id = ConceptName.find_by_name('Yes').concept_id
    pulmonary_tb_concept_id = ConceptName.find_by_name('PULMONARY TUBERCULOSIS').concept_id
    current_ptb_concept_id = ConceptName.find_by_name('PULMONARY TUBERCULOSIS (CURRENT)').concept_id

    who_stages_criteria = ConceptName.find_by_name('Who stages criteria present').concept_id
    registered = []

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date t
      INNER JOIN obs ON t.patient_id = obs.person_id
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
       AND ( (value_coded IN (#{eptb_concept_id}, #{pulmonary_tb_concept_id}, #{current_ptb_concept_id}) AND concept_id = #{who_stages_criteria} )
       OR (concept_id IN (#{eptb_concept_id}, #{pulmonary_tb_concept_id}, #{current_ptb_concept_id}) AND value_coded = #{yes_concept_id}))
      AND voided = 0 AND DATE(obs_datetime) <= DATE(date_enrolled) GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end
  end

  def self.tb_within_the_last_two_years(patients_with_current_tb, start_date, end_date)
    #patients with current episode of tb
    patients_with_current_tb_episode = []
    (patients_with_current_tb || []).each do |patient|
      patients_with_current_tb_episode << patient['patient_id'].to_i
    end

    patients_with_current_tb_episode = [0] if patients_with_current_tb_episode.blank?

    #Pulmonary tuberculosis within the last 2 years
    pulmonary_tb_within_last_2yrs_concept_id = ConceptName.find_by_name('Pulmonary tuberculosis within the last 2 years').concept_id
    ptb_within_the_past_two_yrs_concept_id = ConceptName.find_by_name('Ptb within the past two years').concept_id
    who_stages_criteria = ConceptName.find_by_name('Who stages criteria present').concept_id
    yes_concept_id = ConceptName.find_by_name('Yes').concept_id
    registered = []

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date t
      INNER JOIN obs ON t.patient_id = obs.person_id
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND ((value_coded IN (#{pulmonary_tb_within_last_2yrs_concept_id}, #{ptb_within_the_past_two_yrs_concept_id}) AND concept_id = #{who_stages_criteria})
      OR (concept_id IN (#{pulmonary_tb_within_last_2yrs_concept_id}, #{ptb_within_the_past_two_yrs_concept_id}) AND value_coded = #{yes_concept_id}))
      AND patient_id NOT IN (#{patients_with_current_tb_episode.join(',')})
      AND voided = 0 AND DATE(obs_datetime) <= DATE(date_enrolled) GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end
  end

  def self.no_tb(total_registered, tb_within_the_last_two_years, current_episode_of_tb)
    total_registered_patients = []
    tb_within_2yrs_patients = []
    current_tb_episode_patients = []
    result = []

    (total_registered || []).each do |patient|
      total_registered_patients << patient["patient_id"].to_i
    end

    (tb_within_the_last_two_years || []).each do |patient|
      tb_within_2yrs_patients << patient["patient_id"].to_i
    end

    (current_episode_of_tb || []).each do |patient|
      current_tb_episode_patients << patient["patient_id"].to_i
    end

    result = total_registered_patients - (tb_within_2yrs_patients + current_tb_episode_patients)

    return result
  end

  def self.cum_no_tb(cum_total_registered, cum_tb_within_the_last_two_years, cum_current_episode_of_tb)
    total_registered_patients = []
    tb_within_2yrs_patients = []
    current_tb_episode_patients = []
    result = []

    (cum_total_registered || []).each do |patient|
      total_registered_patients << patient["patient_id"].to_i
    end

    (cum_tb_within_the_last_two_years || []).each do |patient|
      tb_within_2yrs_patients << patient["patient_id"].to_i
    end

    (cum_current_episode_of_tb || []).each do |patient|
      current_tb_episode_patients << patient["patient_id"].to_i
    end

    result = total_registered_patients - (tb_within_2yrs_patients + current_tb_episode_patients)
    return result
  end

  def self.children_12_23_months(start_date, end_date)
    reason_concept_id = ConceptName.find_by_name('HIV Infected').concept_id

    registered = []

    (@@reason_for_starting || []).each do |r|
      next unless reason_concept_id == r[:reason_for_starting_concept_id]
      next unless r[:date_enrolled] >= start_date.to_date and r[:date_enrolled] <= end_date.to_date
      registered << r
    end

    return registered
  end

  def self.unknown_other_reason_outside_guidelines(start_date, end_date)
=begin
    All WHO stage 1 and 2 patients that were enrolled before '2016-04-01'
    should be included in this group.
=end
    reason_concept_ids = []
    reason_concept_ids << ConceptName.find_by_name('Unknown').concept_id
    reason_concept_ids << ConceptName.find_by_name('None').concept_id

    registered = []

    (@@reason_for_starting || []).each do |r|
      next unless reason_concept_ids.include?(r[:reason_for_starting_concept_id])
      next unless r[:date_enrolled] >= start_date.to_date and r[:date_enrolled] <= end_date.to_date
      registered << r
    end

    revised_art_guidelines_date = '2016-04-01'.to_date
    who_stage_1_and_2_concept_ids = []
    who_stage_1_and_2_concept_ids << ConceptName.find_by_name('LYMPHOCYTE COUNT BELOW THRESHOLD WITH WHO STAGE 1').concept_id
    who_stage_1_and_2_concept_ids << ConceptName.find_by_name('LYMPHOCYTES').concept_id
    who_stage_1_and_2_concept_ids << ConceptName.find_by_name('LYMPHOCYTE COUNT BELOW THRESHOLD WITH WHO STAGE 2').concept_id
    who_stage_1_and_2_concept_ids << ConceptName.find_by_name('WHO stage I adult').concept_id
    who_stage_1_and_2_concept_ids << ConceptName.find_by_name('WHO stage I peds').concept_id
    who_stage_1_and_2_concept_ids << ConceptName.find_by_name('WHO stage 1').concept_id
    who_stage_1_and_2_concept_ids << ConceptName.find_by_name('WHO stage II adult').concept_id
    who_stage_1_and_2_concept_ids << ConceptName.find_by_name('WHO stage II peds').concept_id


    if start_date.to_date < revised_art_guidelines_date.to_date
    end_date = revised_art_guidelines_date

      (@@reason_for_starting || []).each do |r|
        next unless who_stage_1_and_2_concept_ids.include?(r[:reason_for_starting_concept_id])
        next unless r[:date_enrolled] < end_date
        registered << r
      end
    end
    return registered
  end

  def self.who_stage_four(start_date, end_date)
    reason_concept_ids = []
    reason_concept_ids << ConceptName.find_by_name('WHO stage IV adult').concept_id
    reason_concept_ids << ConceptName.find_by_name('WHO stage IV peds').concept_id
    reason_concept_ids << ConceptName.find_by_name('WHO STAGE 4').concept_id

    registered = []

    (@@reason_for_starting || []).each do |r|
      next unless reason_concept_ids.include?(r[:reason_for_starting_concept_id])
      next unless r[:date_enrolled] >= start_date.to_date and r[:date_enrolled] <= end_date.to_date
      registered << r
    end

    return registered
  end

  def self.who_stage_three(start_date, end_date)
    reason_concept_ids = []
    reason_concept_ids << ConceptName.find_by_name('WHO stage III adult').concept_id
    reason_concept_ids << ConceptName.find_by_name('WHO stage III peds').concept_id
    reason_concept_ids << ConceptName.find_by_name('WHO STAGE 3').concept_id

    registered = []

    (@@reason_for_starting || []).each do |r|
      next unless reason_concept_ids.include?(r[:reason_for_starting_concept_id])
      next unless r[:date_enrolled] >= start_date.to_date and r[:date_enrolled] <= end_date.to_date
      registered << r
    end

    return registered
  end

  def self.pregnant_women(start_date, end_date)
    reason_concept_ids = []
    reason_concept_ids << ConceptName.find_by_name('PATIENT PREGNANT').concept_id
    reason_concept_ids << ConceptName.find_by_name('Is patient pregnant at initiation?').concept_id
    reason_concept_ids << ConceptName.find_by_name('Patient pregnant state').concept_id
    reason_concept_ids << ConceptName.find_by_name('Is patient pregnant?').concept_id

    registered = []

    (@@reason_for_starting || []).each do |r|
      next unless reason_concept_ids.include?(r[:reason_for_starting_concept_id])
      next unless r[:date_enrolled] >= start_date.to_date and r[:date_enrolled] <= end_date.to_date
      registered << r
    end

    return registered
  end

  def self.breastfeeding_mothers(start_date, end_date)
    reason_concept_id = ConceptName.find_by_name('BREASTFEEDING').concept_id

    registered = []

    (@@reason_for_starting || []).each do |r|
      next unless reason_concept_id == r[:reason_for_starting_concept_id]
      next unless r[:date_enrolled] >= start_date.to_date and r[:date_enrolled] <= end_date.to_date
      registered << r
    end

    return registered
  end

  def self.asymptomatic(start_date, end_date)
    #for WHO stage 1 and 2 to be included in asymptomatic, the patients are supposed to
    #be enrolled on HIV program after 2016-04-01

    revised_art_guidelines_date = '2016-04-01'.to_date
    reason_concept_ids = []; asymptomatic_concept_ids = []
    asymptomatic_concept_ids << ConceptName.find_by_name('ASYMPTOMATIC').concept_id
    reason_concept_ids << ConceptName.find_by_name('WHO stage I adult').concept_id
    reason_concept_ids << ConceptName.find_by_name('WHO stage I peds').concept_id
    reason_concept_ids << ConceptName.find_by_name('WHO stage 1').concept_id
    reason_concept_ids << ConceptName.find_by_name('WHO stage II adult').concept_id
    reason_concept_ids << ConceptName.find_by_name('WHO stage II peds').concept_id
    reason_concept_ids << ConceptName.find_by_name('LYMPHOCYTE COUNT BELOW THRESHOLD WITH WHO STAGE 1').concept_id
    reason_concept_ids << ConceptName.find_by_name('LYMPHOCYTES').concept_id
    reason_concept_ids << ConceptName.find_by_name('LYMPHOCYTE COUNT BELOW THRESHOLD WITH WHO STAGE 2').concept_id

    registered = []
    (@@reason_for_starting || []).each do |r|
      next unless asymptomatic_concept_ids.include?(r[:reason_for_starting_concept_id])

      next unless r[:date_enrolled] >= start_date.to_date and r[:date_enrolled] <= end_date.to_date
      registered << r
    end

    if start_date.to_date >= revised_art_guidelines_date.to_date
      start_date = start_date
    else
      start_date = revised_art_guidelines_date
    end

    (@@reason_for_starting || []).each do |r|
      next unless reason_concept_ids.include?(r[:reason_for_starting_concept_id])

      next unless r[:date_enrolled] >= start_date.to_date and r[:date_enrolled] <= end_date.to_date
      registered << r
    end

    return registered
  end

  def self.who_stage_two(start_date, end_date)
    reason_concept_ids = []
    reason_concept_ids << ConceptName.find_by_name('CD4 COUNT LESS THAN OR EQUAL TO 750').concept_id
    reason_concept_ids << ConceptName.find_by_name('CD4 count less than or equal to 500').concept_id
    reason_concept_ids << ConceptName.find_by_name('CD4 COUNT LESS THAN OR EQUAL TO 350').concept_id
    reason_concept_ids << ConceptName.find_by_name('CD4 COUNT LESS THAN OR EQUAL TO 250').concept_id

    registered = []

    (@@reason_for_starting || []).each do |r|
      next unless reason_concept_ids.include?(r[:reason_for_starting_concept_id])
      next unless r[:date_enrolled] >= start_date.to_date and r[:date_enrolled] <= end_date.to_date
      registered << r
    end

    return registered
  end

  def self.confirmed_hiv_infection_in_infants_pcr(start_date, end_date)
    reason_concept_id = ConceptName.find_by_name('HIV PCR').concept_id

    registered = []

    (@@reason_for_starting || []).each do |r|
      next unless (r[:reason_for_starting_concept_id] == reason_concept_id)
      next unless r[:date_enrolled] >= start_date.to_date and r[:date_enrolled] <= end_date.to_date
      registered << r
    end

    return registered
  end

  def self.presumed_severe_hiv_disease_in_infants(start_date, end_date)
    reason_concept_ids = []
    reason_concept_ids << ConceptName.find_by_name('PRESUMED SEVERE HIV').concept_id
    reason_concept_ids << ConceptName.find_by_name('PRESUMED SEVERE HIV CRITERIA IN INFANTS').concept_id

    registered = []

    (@@reason_for_starting || []).each do |r|
      next unless reason_concept_ids.include?(r[:reason_for_starting_concept_id])
      next unless r[:date_enrolled] >= start_date.to_date and r[:date_enrolled] <= end_date.to_date
      registered << r
    end

    return registered
  end

  def self.unknown_age(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND (age_at_initiation IS NULL OR age_at_initiation < 0 OR birthdate IS NULL)
      GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.adults_at_art_initiation(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND age_at_initiation > 14 GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.children_24_months_14_years_at_art_initiation(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND age_at_initiation BETWEEN  2 AND 14 GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.children_below_24_months_at_art_initiation(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND (age_at_initiation >= 0 AND age_at_initiation < 2) GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.non_pregnant_females(start_date, end_date, pregnant_women = [])
    registered = [] ; pregnant_women_ids = []
    (pregnant_women || []).each do |patient|
      pregnant_women_ids << patient
    end
    pregnant_women_ids = [0] if pregnant_women_ids.blank?

    data = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND (gender = 'F' OR gender = 'Female')
      AND t.patient_id NOT IN(#{pregnant_women_ids.join(',')}) GROUP BY patient_id;
EOF

    (data || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.pregnant_females_all_ages(start_date, end_date)
    registered = [] ; patient_id_plus_date_enrolled = []

    yes_concept_id = ConceptName.find_by_name('Yes').concept_id
    preg_concept_id = ConceptName.find_by_name('IS PATIENT PREGNANT?').concept_id
    patient_preg_concept_id = ConceptName.find_by_name('PATIENT PREGNANT').concept_id
    preg_at_initiation_concept_id = ConceptName.find_by_name('PREGNANT AT INITIATION?').concept_id

    #(patient_id_plus_date_enrolled || []).each do |patient_id, date_enrolled|
      registered = ActiveRecord::Base.connection.select_all <<EOF
              SELECT t.* , o.value_coded FROM temp_earliest_start_date t
                INNER JOIN obs o ON o.person_id = t.patient_id AND o.voided = 0
              WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
              AND (gender = 'F' OR gender = 'Female')
              AND o.concept_id IN (#{preg_concept_id} , #{patient_preg_concept_id}, #{preg_at_initiation_concept_id})
              AND (gender = 'F' OR gender = 'Female')
              AND DATE(o.obs_datetime) = DATE(t.earliest_start_date)
              GROUP BY patient_id
              HAVING value_coded = #{yes_concept_id};
EOF
    pregnant_at_initiation = ActiveRecord::Base.connection.select_all <<EOF
              SELECT patient_id, patient_reason_for_starting_art(patient_id) reason_concept_id
              FROM temp_earliest_start_date
              WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
              AND (gender = 'F' OR gender = 'Female')
              GROUP BY patient_id
              HAVING reason_concept_id IN (1755, 7972, 6131);
EOF
    pregnant_at_initiation_ids = []
    (pregnant_at_initiation || []).each do |patient|
      pregnant_at_initiation_ids << patient['patient_id'].to_i
    end

    if pregnant_at_initiation_ids.blank?
      pregnant_at_initiation_ids = [0]
    end

    transfer_ins_women = ActiveRecord::Base.connection.select_all <<EOF
              SELECT patient_id, re_initiated_check(patient_id, date_enrolled) re_initiated
              FROM temp_earliest_start_date
              WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
              AND DATE(date_enrolled) != DATE(earliest_start_date)
              AND (gender = 'F' OR gender = 'Female')
              AND patient_id IN (#{pregnant_at_initiation_ids.join(',')})
              GROUP BY patient_id
              HAVING re_initiated != 'Re-initiated';
EOF

    transfer_ins_preg_women = []; all_pregnant_females = []
    (transfer_ins_women || []).each do |patient|
      if patient['patient_id'].to_i != 0
        transfer_ins_preg_women << patient['patient_id'].to_i
      end
    end

    (registered || []).each do |patient|
      if patient['patient_id'].to_i != 0
        all_pregnant_females << patient['patient_id'].to_i
      end
    end

    all_pregnant_females = (all_pregnant_females + transfer_ins_preg_women).uniq
    return all_pregnant_females
  end

  def self.males(start_date, end_date)
    registered = []
    data = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND (gender = 'Male' OR gender = 'M') GROUP BY patient_id;
EOF

    (data || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.transfer_in(start_date, end_date)
    registered = []
    re_initiated_on_art_patient_ids = []

    data = ActiveRecord::Base.connection.select_all <<EOF
      SELECT patient_id, re_initiated_check(patient_id, date_enrolled) re_initiated FROM temp_earliest_start_date
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND DATE(date_enrolled) != DATE(earliest_start_date)
      GROUP BY patient_id
      HAVING re_initiated != 'Re-initiated';
EOF

    (data || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.re_initiated_on_art(start_date, end_date)
    registered = []
    data = ActiveRecord::Base.connection.select_all <<EOF
      SELECT patient_id, re_initiated_check(patient_id, date_enrolled) re_initiated FROM temp_earliest_start_date
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND DATE(date_enrolled) != DATE(earliest_start_date)
      GROUP BY patient_id
      HAVING re_initiated = 'Re-initiated';
EOF

    (data || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.initiated_on_art_first_time(start_date, end_date)
    registered = []
    data = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND DATE(date_enrolled) = DATE(earliest_start_date)
      GROUP BY patient_id;
EOF

    (data || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.get_cum_start_date
    cum_start_date = ActiveRecord::Base.connection.select_value <<EOF
      SELECT MIN(date_enrolled) FROM temp_earliest_start_date;
EOF

    return cum_start_date.to_date rescue nil
  end

  def self.total_registered(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM temp_earliest_start_date
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}' GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

    return registered
  end


end
