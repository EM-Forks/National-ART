class FlatTablesCohort


  def self.get_indicators(start_date, end_date)
  time_started = Time.now().strftime('%Y-%m-%d %H:%M:%S')

    ActiveRecord::Base.connection.execute <<EOF
      DROP TABLE IF EXISTS `temp_patient_pregnant`;
EOF


    ActiveRecord::Base.connection.execute <<EOF
      CREATE TABLE temp_patient_pregnant
        SELECT `patient_id`, `patient_pregnant`, `patient_pregnant_v_date` AS `visit_date`
        FROM `flat_table1` 
        WHERE `patient_pregnant` IS NOT NULL
        UNION ALL
        SELECT `patient_id`, `patient_pregnant`, `visit_date` AS `visit_date`
        FROM `flat_table2`
        WHERE `patient_pregnant` IS NOT NULL
        ORDER BY `patient_id`, `visit_date`;
EOF


ActiveRecord::Base.connection.execute <<EOF
  DROP FUNCTION IF EXISTS `last_text_for_obs`;
EOF

    ActiveRecord::Base.connection.execute <<EOF
CREATE FUNCTION last_text_for_obs(my_patient_id INT, my_encounter_type_id INT, my_concept_id INT, my_regimem_given INT, unknown_regimen_value INT, my_end_date DATETIME) RETURNS varchar(255)

BEGIN
  SET @obs_value = NULL;
  SET @encounter_id = NULL;

  SELECT o.encounter_id INTO @encounter_id FROM encounter e
  	INNER JOIN obs o ON e.encounter_id = o.encounter_id AND o.concept_id IN (my_concept_id, @unknown_drug_concept_id) AND o.voided = 0
  WHERE e.encounter_type = my_encounter_type_id
  AND e.voided = 0
  AND e.patient_id = my_patient_id
  AND e.encounter_datetime <= my_end_date
  ORDER BY e.encounter_datetime DESC LIMIT 1;

  SELECT cn.name INTO @obs_value FROM obs o
  	LEFT JOIN concept_name cn ON o.value_coded = cn.concept_id AND cn.concept_name_type = 'FULLY_SPECIFIED'
  WHERE encounter_id = @encounter_id
  AND o.voided = 0
  AND o.concept_id = my_concept_id
  AND o.voided = 0 LIMIT 1;

  IF @obs_value IS NULL THEN
    SELECT 'unknown_drug_value' INTO @obs_value FROM obs
    WHERE encounter_id = @encounter_id
    AND voided = 0
    AND concept_id = my_regimem_given
    AND (value_coded = unknown_regimen_value OR value_text = 'Unknown')
    AND voided = 0 LIMIT 1;
  END IF;

  IF @obs_value IS NULL THEN
    SELECT value_text INTO @obs_value FROM obs
    WHERE encounter_id = @encounter_id
    AND voided = 0
    AND concept_id = my_concept_id
    AND voided = 0 LIMIT 1;
  END IF;

  IF @obs_value IS NULL THEN
    SELECT value_numeric INTO @obs_value FROM obs
    WHERE encounter_id = @encounter_id
    AND voided = 0
    AND concept_id = my_concept_id
    AND voided = 0 LIMIT 1;
  END IF;

  RETURN @obs_value;
END;
EOF

    ActiveRecord::Base.connection.execute <<EOF
      DROP FUNCTION IF EXISTS `drug_pill_count`;
EOF

    ActiveRecord::Base.connection.execute <<EOF
CREATE FUNCTION `drug_pill_count`(my_patient_id INT, my_drug_id INT, my_date DATE) RETURNS decimal(10,0)
BEGIN
  DECLARE done INT DEFAULT FALSE;
  DECLARE my_pill_count, my_total_text, my_total_numeric DECIMAL;

  DECLARE cur1 CURSOR FOR SELECT SUM(ob.value_numeric), SUM(CAST(ob.value_text AS DECIMAL)) FROM obs ob
                        INNER JOIN drug_order do ON ob.order_id = do.order_id
                        INNER JOIN orders o ON do.order_id = o.order_id
                    WHERE ob.person_id = my_patient_id
                        AND ob.concept_id = 2540
                        AND ob.voided = 0
                        AND o.voided = 0
                        AND do.drug_inventory_id = my_drug_id
                        AND DATE(ob.obs_datetime) = my_date
                    GROUP BY ob.person_id;

  DECLARE cur2 CURSOR FOR SELECT SUM(ob.value_numeric) FROM obs ob
                    WHERE ob.person_id = my_patient_id
                        AND ob.concept_id = (SELECT concept_id FROM drug WHERE drug_id = my_drug_id)
                        AND ob.voided = 0
                        AND DATE(ob.obs_datetime) = my_date
                    GROUP BY ob.person_id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  OPEN cur1;

  SET my_pill_count = 0;

  read_loop: LOOP
    FETCH cur1 INTO my_total_numeric, my_total_text;

    IF done THEN
      CLOSE cur1;
      LEAVE read_loop;
    END IF;

        IF my_total_numeric IS NULL THEN
            SET my_total_numeric = 0;
        END IF;

        IF my_total_text IS NULL THEN
            SET my_total_text = 0;
        END IF;

        SET my_pill_count = my_total_numeric + my_total_text;
    END LOOP;

  OPEN cur2;
  SET done = false;

  read_loop: LOOP
    FETCH cur2 INTO my_total_numeric;

    IF done THEN
      CLOSE cur2;
      LEAVE read_loop;
    END IF;

        IF my_total_numeric IS NULL THEN
            SET my_total_numeric = 0;
        END IF;

        SET my_pill_count = my_total_numeric + my_pill_count;
    END LOOP;

  RETURN my_pill_count;
END;
EOF

    ActiveRecord::Base.connection.execute <<EOF
      DROP FUNCTION IF EXISTS `current_defaulter`;
EOF

    ActiveRecord::Base.connection.execute <<EOF
CREATE FUNCTION `current_defaulter`(my_patient_id INT, my_end_date DATETIME) RETURNS int(1)
BEGIN
  DECLARE done INT DEFAULT FALSE;
  DECLARE my_start_date, my_expiry_date, my_obs_datetime DATETIME;
  DECLARE my_daily_dose, my_quantity, my_pill_count, my_total_text, my_total_numeric DECIMAL;
  DECLARE my_drug_id, flag INT;

  DECLARE cur1 CURSOR FOR SELECT d.drug_inventory_id, o.start_date, d.equivalent_daily_dose daily_dose, d.quantity, o.start_date FROM drug_order d
    INNER JOIN arv_drug ad ON d.drug_inventory_id = ad.drug_id
    INNER JOIN orders o ON d.order_id = o.order_id
      AND d.quantity > 0
      AND o.voided = 0
      AND o.start_date <= my_end_date
      AND o.patient_id = my_patient_id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  SELECT MAX(o.start_date) INTO @obs_datetime FROM drug_order d
    INNER JOIN arv_drug ad ON d.drug_inventory_id = ad.drug_id
    INNER JOIN orders o ON d.order_id = o.order_id
      AND d.quantity > 0
      AND o.voided = 0
      AND o.start_date <= my_end_date
      AND o.patient_id = my_patient_id
    GROUP BY o.patient_id;

  OPEN cur1;

  SET flag = 0;

  read_loop: LOOP
    FETCH cur1 INTO my_drug_id, my_start_date, my_daily_dose, my_quantity, my_obs_datetime;

    IF done THEN
      CLOSE cur1;
      LEAVE read_loop;
    END IF;

    IF DATE(my_obs_datetime) = DATE(@obs_datetime) THEN

      IF my_daily_dose = 0 OR LENGTH(my_daily_dose) < 1 OR my_daily_dose IS NULL THEN
        SET my_daily_dose = 1;
      END IF;

            SET my_pill_count = drug_pill_count(my_patient_id, my_drug_id, my_obs_datetime);

            SET @expiry_date = ADDDATE(DATE_SUB(my_start_date, INTERVAL 2 DAY), ((my_quantity + my_pill_count)/my_daily_dose));

      IF my_expiry_date IS NULL THEN
        SET my_expiry_date = @expiry_date;
      END IF;

      IF @expiry_date < my_expiry_date THEN
        SET my_expiry_date = @expiry_date;
            END IF;
        END IF;
    END LOOP;

    IF TIMESTAMPDIFF(day, my_expiry_date, my_end_date) > 60 THEN
        SET flag = 1;
    END IF;

  RETURN flag;
END;
EOF

    ActiveRecord::Base.connection.execute <<EOF
      DROP FUNCTION IF EXISTS `current_defaulter_date`;
EOF

    ActiveRecord::Base.connection.execute <<EOF
CREATE FUNCTION current_defaulter_date(my_patient_id INT, my_end_date date) RETURNS varchar(25)
DETERMINISTIC
BEGIN
DECLARE done INT DEFAULT FALSE;
  DECLARE my_start_date, my_expiry_date, my_obs_datetime, my_defaulted_date DATETIME;
  DECLARE my_daily_dose, my_quantity, my_pill_count, my_total_text, my_total_numeric DECIMAL;
  DECLARE my_drug_id, flag INT;

  DECLARE cur1 CURSOR FOR SELECT d.drug_inventory_id, o.start_date, d.equivalent_daily_dose daily_dose, d.quantity, o.start_date FROM drug_order d
    INNER JOIN arv_drug ad ON d.drug_inventory_id = ad.drug_id
    INNER JOIN orders o ON d.order_id = o.order_id
      AND d.quantity > 0
      AND o.voided = 0
      AND o.start_date <= my_end_date
      AND o.patient_id = my_patient_id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  SELECT MAX(o.start_date) INTO @obs_datetime FROM drug_order d
    INNER JOIN arv_drug ad ON d.drug_inventory_id = ad.drug_id
    INNER JOIN orders o ON d.order_id = o.order_id
      AND d.quantity > 0
      AND o.voided = 0
      AND o.start_date <= my_end_date
      AND o.patient_id = my_patient_id
    GROUP BY o.patient_id;

  OPEN cur1;

  SET flag = 0;

  read_loop: LOOP
    FETCH cur1 INTO my_drug_id, my_start_date, my_daily_dose, my_quantity, my_obs_datetime;

    IF done THEN
      CLOSE cur1;
      LEAVE read_loop;
    END IF;

    IF DATE(my_obs_datetime) = DATE(@obs_datetime) THEN

      IF my_daily_dose = 0 OR my_daily_dose IS NULL OR LENGTH(my_daily_dose) < 1 THEN
        SET my_daily_dose = 1;
      END IF;

      SET my_pill_count = drug_pill_count(my_patient_id, my_drug_id, my_obs_datetime);

      SET @expiry_date = ADDDATE(my_start_date, ((my_quantity + my_pill_count)/my_daily_dose));

      IF my_expiry_date IS NULL THEN
        SET my_expiry_date = @expiry_date;
      END IF;

      IF @expiry_date < my_expiry_date THEN
        SET my_expiry_date = @expiry_date;
        END IF;
      END IF;
    END LOOP;

    IF DATEDIFF(my_end_date, my_expiry_date) > 60 THEN
      SET my_defaulted_date = ADDDATE(my_expiry_date, 60);
    END IF;

  RETURN my_defaulted_date;
END;
EOF


    ActiveRecord::Base.connection.execute <<EOF
      DROP FUNCTION IF EXISTS `patient_outcome`;
EOF

    ActiveRecord::Base.connection.execute <<EOF
CREATE FUNCTION patient_outcome(patient_id INT, visit_date DATETIME) RETURNS varchar(25)
DETERMINISTIC
BEGIN
DECLARE set_program_id INT;
DECLARE set_patient_state INT;
DECLARE set_outcome varchar(25);
DECLARE set_date_started date;
DECLARE set_patient_state_died INT;
DECLARE set_died_concept_id INT;
DECLARE set_timestamp DATETIME;

SET set_timestamp = DATE_FORMAT(visit_date, '%Y-%m-%d 23:59:59');
SET set_program_id = (SELECT program_id FROM program WHERE name ="HIV PROGRAM" LIMIT 1);

SET set_patient_state = (SELECT state FROM `patient_state` INNER JOIN patient_program p ON p.patient_program_id = patient_state.patient_program_id AND p.program_id = set_program_id WHERE (patient_state.voided = 0 AND p.voided = 0 AND p.program_id = program_id AND DATE(start_date) <= visit_date AND p.patient_id = patient_id) AND (patient_state.voided = 0) ORDER BY start_date DESC, patient_state.patient_state_id DESC, patient_state.date_created DESC LIMIT 1);

IF set_patient_state = 1 THEN
  SET set_patient_state = current_defaulter(patient_id, set_timestamp);

  IF set_patient_state = 1 THEN
    SET set_outcome = 'Defaulted';
  ELSE
    SET set_outcome = 'Pre-ART (Continue)';
  END IF;
END IF;

IF set_patient_state = 2   THEN
  SET set_outcome = 'Patient transferred out';
END IF;

IF set_patient_state = 3 OR set_patient_state = 127 THEN
  SET set_outcome = 'Patient died';
END IF;

/* ............... This block of code checks if the patient has any state that is "died" */
IF set_patient_state != 3 AND set_patient_state != 127 THEN
  SET set_patient_state_died = (SELECT state FROM `patient_state` INNER JOIN patient_program p ON p.patient_program_id = patient_state.patient_program_id AND p.program_id = set_program_id WHERE (patient_state.voided = 0 AND p.voided = 0 AND p.program_id = program_id AND DATE(start_date) <= visit_date AND p.patient_id = patient_id) AND (patient_state.voided = 0) AND state = 3 ORDER BY patient_state.patient_state_id DESC, patient_state.date_created DESC, start_date DESC LIMIT 1);

  SET set_died_concept_id = (SELECT concept_id FROM concept_name WHERE name = 'Patient died' LIMIT 1);

  IF set_patient_state_died IN(SELECT program_workflow_state_id FROM program_workflow_state WHERE concept_id = set_died_concept_id AND retired = 0) THEN
    SET set_outcome = 'Patient died';
    SET set_patient_state = 3;
  END IF;
END IF;
/* ....................  ends here .................... */


IF set_patient_state = 6 THEN
  SET set_outcome = 'Treatment stopped';
END IF;

IF set_patient_state = 7 THEN
  SET set_patient_state = current_defaulter(patient_id, set_timestamp);

  IF set_patient_state = 1 THEN
    SET set_outcome = 'Defaulted';
  END IF;

  IF set_patient_state = 0 THEN
    SET set_outcome = 'On antiretrovirals';
  END IF;
END IF;

IF set_outcome IS NULL THEN
  SET set_patient_state = current_defaulter(patient_id, set_timestamp);

  IF set_patient_state = 1 THEN
    SET set_outcome = 'Defaulted';
  END IF;

  IF set_outcome IS NULL THEN
    SET set_outcome = 'Unknown';
  END IF;

END IF;

RETURN set_outcome;
END;
EOF

    ActiveRecord::Base.connection.execute <<EOF
      DROP FUNCTION IF EXISTS `re_initiated_check`;
EOF

    ActiveRecord::Base.connection.execute <<EOF
CREATE FUNCTION re_initiated_check(set_patient_id INT, set_date_enrolled DATE) RETURNS VARCHAR(15)
DETERMINISTIC
BEGIN
DECLARE re_initiated VARCHAR(15) DEFAULT 'N/A';
DECLARE check_one INT DEFAULT 0;
DECLARE check_two INT DEFAULT 0;

DECLARE yes_concept INT;
DECLARE no_concept INT;
DECLARE date_art_last_taken_concept INT;
DECLARE taken_arvs_concept INT;

set yes_concept = (SELECT concept_id FROM concept_name WHERE name ='YES' LIMIT 1);
set no_concept = (SELECT concept_id FROM concept_name WHERE name ='NO' LIMIT 1);
set date_art_last_taken_concept = (SELECT concept_id FROM concept_name WHERE name ='DATE ART LAST TAKEN' LIMIT 1);
set taken_arvs_concept = (SELECT concept_id FROM concept_name WHERE name ='HAS THE PATIENT TAKEN ART IN THE LAST TWO MONTHS' LIMIT 1);

set check_one = (SELECT esd.patient_id FROM temp_earliest_start_date esd INNER JOIN clinic_registration_encounter e ON esd.patient_id = e.patient_id INNER JOIN ever_registered_obs AS ero ON e.encounter_id = ero.encounter_id INNER JOIN obs o ON o.encounter_id = e.encounter_id AND o.concept_id = date_art_last_taken_concept AND o.voided = 0 WHERE ((o.concept_id = date_art_last_taken_concept AND (DATEDIFF(o.obs_datetime,o.value_datetime)) > 14)) AND esd.date_enrolled = set_date_enrolled AND esd.patient_id = set_patient_id GROUP BY esd.patient_id);

set check_two = (SELECT esd.patient_id FROM temp_earliest_start_date esd INNER JOIN clinic_registration_encounter e ON esd.patient_id = e.patient_id INNER JOIN ever_registered_obs AS ero ON e.encounter_id = ero.encounter_id INNER JOIN obs o ON o.encounter_id = e.encounter_id AND o.concept_id = taken_arvs_concept AND o.voided = 0 WHERE  ((o.concept_id = taken_arvs_concept AND o.value_coded = no_concept)) AND esd.date_enrolled = set_date_enrolled AND esd.patient_id = set_patient_id GROUP BY esd.patient_id);

if check_one >= 1 then set re_initiated ="Re-initiated";
elseif check_two >= 1 then set re_initiated ="Re-initiated";
end if;


RETURN re_initiated;
END;
EOF

    ActiveRecord::Base.connection.execute <<EOF
      DROP FUNCTION IF EXISTS `patient_died_in`;
EOF

    ActiveRecord::Base.connection.execute <<EOF
CREATE FUNCTION patient_died_in(set_patient_id INT, set_status VARCHAR(25), date_enrolled DATE) RETURNS varchar(25)
DETERMINISTIC
BEGIN
DECLARE set_outcome varchar(25) default 'N/A';
DECLARE date_of_death DATE;
DECLARE num_of_days INT;

IF set_status = 'Patient died' THEN

  SET date_of_death = (SELECT death_date FROM flat_cohort_table WHERE patient_id = set_patient_id);

  IF date_of_death IS NULL THEN
    RETURN 'Unknown';
  END IF;


  set num_of_days = (TIMESTAMPDIFF(day, date(date_enrolled), date(date_of_death)));

  IF num_of_days <= 30 THEN set set_outcome ="1st month";
  ELSEIF num_of_days <= 60 THEN set set_outcome ="2nd month";
  ELSEIF num_of_days <= 91 THEN set set_outcome ="3rd month";
  ELSEIF num_of_days > 91 THEN set set_outcome ="4+ months";
  ELSEIF num_of_days IS NULL THEN set set_outcome = "Unknown";
  END IF;


END IF;

RETURN set_outcome;
END;
EOF


#=end
      #Get earliest date enrolled
      cum_start_date = self.get_cum_start_date
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
    cohort.total_alive_and_on_art                      = self.total_alive_and_on_art('On antiretrovirals', end_date)
    cohort.died_within_the_1st_month_of_art_initiation = self.died_in('1st month')
    cohort.died_within_the_2nd_month_of_art_initiation = self.died_in('2nd month')
    cohort.died_within_the_3rd_month_of_art_initiation = self.died_in('3rd month')
    cohort.died_after_the_3rd_month_of_art_initiation  = self.died_in('4+ months')
    cohort.died_total                                  = self.died_total('Patient died', end_date)
    cohort.defaulted                                   = self.defaulted('Defaulted', end_date)
    cohort.stopped_art                                 = self.stopped_art('Treatment stopped', end_date)
    cohort.transfered_out                              = self.transfered_out('Patient transferred out', end_date)
    cohort.unknown_outcome                             = self.unknown_outcome('Pre-ART (Continue)', end_date)

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
    cohort.unknown_side_effects = self.unknown_side_effects(cohort.total_alive_and_on_art, start_date, end_date)
    cohort.total_patients_with_side_effects = self.total_patients_with_side_effects(cohort.total_alive_and_on_art, start_date, end_date)
    cohort.total_patients_without_side_effects = self.total_patients_without_side_effects(cohort.total_alive_and_on_art, cohort.total_patients_with_side_effects, cohort.unknown_side_effects)
=begin
    TB Status
    Alive and On ART with 'TB Status' observation value of 'TB not Suspected' or 'TB Suspected'
    or 'TB confirmed and on Treatment', or 'TB confirmed and not on Treatment' or 'Unknown TB status'
    during their latest HIV Clinic Consultaiton encounter in the reporting period
=end
    #@@tb_status = self.cal_tb_status(cohort.total_alive_and_on_art, end_date)

    cohort.tb_suspected = self.tb_suspected(cohort.total_alive_and_on_art, start_date, end_date)
    cohort.tb_not_suspected = self.tb_not_suspected(cohort.total_alive_and_on_art, start_date, end_date)
    cohort.tb_confirmed_on_tb_treatment = self.confirmed_tb_on_treatment(cohort.total_alive_and_on_art, start_date, end_date)
    cohort.tb_confirmed_currently_not_yet_on_tb_treatment = self.confirmed_tb_not_on_treatment(cohort.total_alive_and_on_art, start_date, end_date)
    cohort.unknown_tb_status = self.unknown_tb_status(cohort.total_alive_and_on_art, start_date, end_date)

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
    cohort.total_pregnant_women = self.total_pregnant_women(cohort.total_alive_and_on_art, end_date)
    cohort.total_breastfeeding_women = self.total_breastfeeding_women(cohort.total_alive_and_on_art, end_date)
    cohort.total_other_patients = self.total_other_patients(cohort.total_alive_and_on_art, cohort.total_breastfeeding_women, cohort.total_pregnant_women)

=begin
    Patients with CPT dispensed at least once before end of quarter and on ARVs
=end
    cohort.total_patients_on_arvs_and_cpt = self.total_patients_on_arvs_and_cpt(cohort.total_alive_and_on_art, start_date, end_date)

=begin
    Patients with IPT dispensed at least once before end of quarter and on ARVS
=end
    cohort.total_patients_on_arvs_and_ipt = self.total_patients_on_arvs_and_ipt(cohort.total_alive_and_on_art, start_date, end_date)

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

  private

  def self.total_patients_with_screened_bp(patients_list, start_date, end_date)
    patient_ids = []
    (patients_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?
    result = []

    results = ActiveRecord::Base.connection.select_all <<EOF
                SELECT fct.patient_id, ft2.visit_date, ft2.diastolic_blood_pressure, ft2.systolic_blood_pressure
                FROM flat_cohort_table fct
                	INNER JOIN flat_table2 ft2 ON ft2.patient_id = fct.patient_id
                WHERE ft2.systolic_blood_pressure IS NOT NULL and ft2.systolic_blood_pressure IS NOT NULL
                AND (ft2.visit_date <= '#{end_date}')
                AND fct.patient_id IN (#{patient_ids.join(',')})
                AND ft2.visit_date = (SELECT max(f2.visit_date) FROM flat_table2 f2
                                      WHERE f2.systolic_blood_pressure IS NOT NULL and f2.systolic_blood_pressure IS NOT NULL
                                      AND f2.patient_id = ft2.patient_id
                                      AND f2.visit_date <= '#{end_date}')
                GROUP BY fct.patient_id;
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
      SELECT patient_id, earliest_start_date, date_enrolled, gender FROM flat_cohort_table
      WHERE (gender = 'F' OR gender = 'Female') AND patient_id IN  (#{patient_ids.join(',')})
      AND date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      GROUP BY patient_id;
EOF

    (all_women || []).each do |patient|
        patient_list << patient['patient_id'].to_i
    end
    patient_list = [] if patient_list.blank?

    results = ActiveRecord::Base.connection.select_all <<EOF
                  SELECT fct.patient_id, ft2.visit_date, ft2.family_planning_method, ft2.currently_using_family_planning_method
                  FROM flat_cohort_table fct
                        INNER JOIN flat_table2 ft2 ON ft2.patient_id = fct.patient_id
                  WHERE (ft2.family_planning_method NOT IN ('None', 'No')
    					           OR ft2.currently_using_family_planning_method NOT IN ('None', 'No'))
                  AND (ft2.visit_date BETWEEN '#{start_date}' AND '#{end_date}')
                  AND fct.patient_id IN (#{patient_list.join(',')})
                  AND visit_date = (SELECT max(f2.visit_date) FROM flat_table2 f2
                                       WHERE f2.patient_id = ft2.patient_id
                                       AND f2.visit_date BETWEEN '#{start_date}' AND '#{end_date}'
                                       AND (f2.family_planning_method IS NOT NULL
                                          OR ft2.currently_using_family_planning_method IS NOT NULL))
                    GROUP BY fct.patient_id;
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
                SELECT fct.patient_id, ft2.visit_date, ft2.drug_name1, ft2.drug_name2, ft2.drug_name3, ft2.drug_name4, ft2.drug_name5
                FROM flat_cohort_table fct
                  INNER JOIN flat_table2 ft2 ON ft2.patient_id = fct.patient_id
                WHERE ((ft2.drug_name1 like '%Isoniazid%' OR ft2.drug_name1 like '%Pyridoxine%')
                	OR (ft2.drug_name2 like '%Isoniazid%' OR ft2.drug_name2 like '%Pyridoxine%')
                    OR (ft2.drug_name3 like '%Isoniazid%' OR ft2.drug_name3 like '%Pyridoxine%')
                    OR (ft2.drug_name4 like '%Isoniazid%' OR ft2.drug_name4 like '%Pyridoxine%')
                    OR (ft2.drug_name5 like '%Isoniazid%' OR ft2.drug_name5 like '%Pyridoxine%'))
                AND (ft2.visit_date BETWEEN '#{start_date}' AND '#{end_date}')
                AND fct.patient_id IN (#{patient_ids.join(',')})
                AND visit_date = (SELECT max(visit_date) FROM flat_table2 f2
                                   WHERE f2.patient_id = ft2.patient_id
                                   AND f2.visit_date BETWEEN '#{start_date}' AND '#{end_date}'
                                   AND ((f2.drug_name1 like '%Isoniazid%' OR f2.drug_name1 like '%Pyridoxine%')
                						OR (f2.drug_name2 like '%Isoniazid%' OR f2.drug_name2 like '%Pyridoxine%')
                						OR (f2.drug_name3 like '%Isoniazid%' OR f2.drug_name3 like '%Pyridoxine%')
                						OR (f2.drug_name4 like '%Isoniazid%' OR f2.drug_name4 like '%Pyridoxine%')
                						OR (f2.drug_name5 like '%Isoniazid%' OR f2.drug_name5 like '%Pyridoxine%')))
                GROUP BY fct.patient_id;
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
                SELECT fct.patient_id, ft2.visit_date, ft2.drug_name1, ft2.drug_name2, ft2.drug_name3, ft2.drug_name4, ft2.drug_name5
                FROM flat_cohort_table fct
                  INNER JOIN flat_table2 ft2 ON ft2.patient_id = fct.patient_id
                WHERE (ft2.drug_name1 like '%Cotrimoxazole%'
                	     OR ft2.drug_name2 like '%Cotrimoxazole%'
                       OR ft2.drug_name3 like '%Cotrimoxazole%'
                       OR ft2.drug_name4 like '%Cotrimoxazole%'
                       OR ft2.drug_name5 like '%Cotrimoxazole%')
                AND (ft2.visit_date BETWEEN '#{start_date}' AND '#{end_date}')
                AND fct.patient_id IN (#{patient_ids.join(',')})
                AND visit_date = (SELECT max(visit_date) FROM flat_table2 f2
                                   WHERE f2.patient_id = ft2.patient_id
                                   AND f2.visit_date BETWEEN '#{start_date}' AND '#{end_date}'
                                   AND (f2.drug_name1 LIKE '%Cotrimoxazole%'
                            						OR f2.drug_name2 LIKE '%Cotrimoxazole%'
                            						OR f2.drug_name3 LIKE '%Cotrimoxazole%'
                            						OR f2.drug_name4 LIKE '%Cotrimoxazole%'
                            						OR f2.drug_name5 LIKE '%Cotrimoxazole%'))
                GROUP BY fct.patient_id;
EOF
    total_percent = (((results.count).to_f / (patient_ids.count).to_f) * 100).to_i
    return total_percent
  end

  def self.total_breastfeeding_women(patients_list, end_date)
    patient_ids = []
    (patients_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?
    result = []

    total_pregnant_females = []
    (total_pregnant_women(patients_list, end_date) || []).each do |person|
      total_pregnant_females << person['patient_id'].to_i
    end

    return [] if total_pregnant_females.blank?

    results = ActiveRecord::Base.connection.select_all <<EOF
              SELECT fct.patient_id, ft2.visit_date, ft2.patient_breastfeeding
              FROM flat_cohort_table fct
                INNER JOIN flat_table2 ft2  ON ft2.patient_id = fct.patient_id
              WHERE ft2.patient_breastfeeding = 'Yes' AND ft2.patient_breastfeeding IS NOT NULL
              AND (ft2.visit_date <= '#{end_date}')
              AND fct.patient_id IN (#{patient_ids.join(',')})
              AND fct.patient_id NOT IN (#{total_pregnant_females.join(',')})
              AND ft2.visit_date = (SELECT max(visit_date) from flat_table2 f2
              					  WHERE f2.patient_id = fct.patient_id
              					  AND f2.visit_date <= '#{end_date}'
                          AND f2.patient_breastfeeding IS NOT NULL)
              GROUP BY fct.patient_id;
EOF
    return results
  end

  def self.total_pregnant_women(patients_list, end_date)
    patient_ids = []
    (patients_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?
    result = []

    results = ActiveRecord::Base.connection.select_all <<EOF
                SELECT fct.patient_id, ft2.visit_date, ft2.patient_pregnant
                FROM flat_cohort_table fct
                  INNER JOIN flat_table2 ft2 ON ft2.patient_id = fct.patient_id
                WHERE ft2.patient_pregnant = 'Yes' AND ft2.patient_pregnant IS NOT NULL
                AND (ft2.visit_date <= '#{end_date}')
                AND fct.patient_id IN (#{patient_ids.join(',')})
                AND ft2.visit_date = (SELECT max(visit_date) from flat_table2 f2
                            WHERE f2.patient_id = ft2.patient_id
                            AND f2.visit_date <= '#{end_date}'
                            AND f2.patient_pregnant IS NOT NULL)
                GROUP BY fct.patient_id;
EOF
    return results
  end

  def self.total_other_patients(patient_list, all_breastfeeding_women, all_pregnant_women)
    patient_ids = []; all_pregnant_women_ids = []; all_breastfeeding_women_ids = []

    (patient_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    (all_pregnant_women || []).each do |row|
      all_pregnant_women_ids << row['patient_id'].to_i
    end

    (all_breastfeeding_women || []).each do |row|
      all_breastfeeding_women_ids << row['patient_id'].to_i
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
                  SELECT fct.patient_id, visit_date, ft2.what_was_the_patient_adherence_for_this_drug1, ft2.what_was_the_patient_adherence_for_this_drug2, ft2.what_was_the_patient_adherence_for_this_drug3, ft2.what_was_the_patient_adherence_for_this_drug4, ft2.what_was_the_patient_adherence_for_this_drug5
                  FROM flat_cohort_table fct
                    INNER JOIN flat_table2 ft2 ON ft2.patient_id = fct.patient_id
                  WHERE ft2.visit_date <= '#{end_date}'
                  AND fct.patient_id IN (#{patient_ids.join(',')})
                  AND ft2.visit_date = (SELECT MAX(ft.visit_date) FROM flat_table2 ft
                                        WHERE ft.patient_id = fct.patient_id
                                        AND visit_date <= '#{end_date}'
                                        AND ((ft.what_was_the_patient_adherence_for_this_drug1 != '') 
                                              OR (ft.what_was_the_patient_adherence_for_this_drug2 != '') 
                                              OR (ft.what_was_the_patient_adherence_for_this_drug3 != '') 
                                              OR (ft.what_was_the_patient_adherence_for_this_drug4 != '') 
                                              OR (ft.what_was_the_patient_adherence_for_this_drug5 != '')))
                  GROUP BY fct.patient_id;
EOF
    adherence_results = []
    patient_adherence = []
    patient_unknown_adherence = []
    unknown_patient_adherence = []

    (adherence || []).each do |adh|
      patient_adherence = []
      unless adh['what_was_the_patient_adherence_for_this_drug1'].blank?
        if adh['what_was_the_patient_adherence_for_this_drug1'].match(/unknown/i)
          patient_unknown_adherence << [adh['patient_id'].to_i, "Unknown"]
        else
          patient_adherence <<  adh['what_was_the_patient_adherence_for_this_drug1'].to_f
        end
      end

      unless adh['what_was_the_patient_adherence_for_this_drug2'].blank?
        if adh['what_was_the_patient_adherence_for_this_drug2'].match(/unknown/i)
          patient_unknown_adherence << [adh['patient_id'].to_i, "Unknown"]
        else
          patient_adherence <<  adh['what_was_the_patient_adherence_for_this_drug2'].to_f
        end      
      end

      unless adh['what_was_the_patient_adherence_for_this_drug3'].blank?
        if adh['what_was_the_patient_adherence_for_this_drug3'].match(/unknown/i)
          patient_unknown_adherence << [adh['patient_id'].to_i, "Unknown"]
        else
          patient_adherence <<  adh['what_was_the_patient_adherence_for_this_drug3'].to_f
        end      
      end

      unless adh['what_was_the_patient_adherence_for_this_drug4'].blank?
        if adh['what_was_the_patient_adherence_for_this_drug4'].match(/unknown/i)
          patient_unknown_adherence << [adh['patient_id'].to_i, "Unknown"]
        else
          patient_adherence <<  adh['what_was_the_patient_adherence_for_this_drug4'].to_f
        end      
      end

      unless adh['what_was_the_patient_adherence_for_this_drug5'].blank?
        if adh['what_was_the_patient_adherence_for_this_drug5'].match(/unknown/i)
          patient_unknown_adherence << [adh['patient_id'].to_i, "Unknown"]
        else
          patient_adherence <<  adh['what_was_the_patient_adherence_for_this_drug5'].to_f
        end
      end
        if patient_unknown_adherence.blank?
          adherence_results << [adh['patient_id'].to_i, patient_adherence.min]
        else
          adherence_results << [adh['patient_id'].to_i, 'Unknown']
        end
    end
    

    adherent = [] ; not_adherent = [] ; unknown_adherence = [];

    (adherence_results || []).each do |patient_id, adh|
      if adh == "Unknown"
        unknown_adherence << patient_id ; unknown_adherence = unknown_adherence.uniq
        next
      end unless adherence.blank?


      rate = adh unless adh.blank?
      rate = 0 if rate.blank?

      if rate >= 95
        adherent << patient_id ; adherent = adherent.uniq
      elsif rate < 95
        not_adherent << patient_id ; not_adherent = not_adherent.uniq
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
              SELECT max(obs_datetime) FROM obs WHERE concept_id IN (#{malawi_art_side_effects_concept_id}, #{drug_induced_concept_id})
              AND voided = 0 AND person_id = o.person_id
              AND obs_datetime <= '#{end_date.to_date.strftime('%Y-%m-%d 23:59:59')}'
              AND value_coded = #{unknown_side_effects_concept_id}
            ) GROUP BY person_id
EOF

    (malawi_art_side_effects || []).each do |row|
      result << row
    end
    return result
  end

  def self.tb_suspected(patient_list, start_date, end_date)
    registered = []
    patient_ids = []

    (patient_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table fct
        INNER JOIN flat_table2 ft2 on ft2.patient_id = fct.patient_id
      WHERE fct.date_enrolled <= '#{end_date}'
      AND fct.date_enrolled <> '0000-00-00'
      AND ft2.visit_date = (SELECT MAX(visit_date) FROM flat_table2 WHERE patient_id = fct.patient_id AND visit_date <= '#{end_date}' AND tb_status IS NOT NULL)
      AND fct.patient_id IN (#{patient_ids.join(',')})
      AND ft2.tb_status = 'TB Suspected' GROUP BY fct.patient_id;
EOF
    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.tb_not_suspected(patient_list, start_date, end_date)
    registered = []

    patient_ids = []

    (patient_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table fct
        INNER JOIN flat_table2 ft2 on ft2.patient_id = fct.patient_id
      WHERE fct.date_enrolled <= '#{end_date}'
      AND fct.date_enrolled <> '0000-00-00'
      AND ft2.visit_date = (SELECT MAX(visit_date) FROM flat_table2 WHERE patient_id = fct.patient_id AND visit_date <= '#{end_date}' AND tb_status IS NOT NULL)
      AND fct.patient_id IN (#{patient_ids.join(',')})
      AND ft2.tb_status = 'TB NOT Suspected' GROUP BY fct.patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.confirmed_tb_not_on_treatment(patient_list, start_date, end_date)
    registered = []

    patient_ids = []

    (patient_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table fct
        INNER JOIN flat_table2 ft2 on ft2.patient_id = fct.patient_id
      WHERE fct.date_enrolled <= '#{end_date}'
      AND fct.date_enrolled <> '0000-00-00'
      AND ft2.visit_date = (SELECT MAX(visit_date) FROM flat_table2 WHERE patient_id = fct.patient_id AND visit_date <= '#{end_date}' AND tb_status IS NOT NULL)
      AND fct.patient_id IN (#{patient_ids.join(',')})
      AND ft2.tb_status IN ('TB Confirmed NOT on treatment', 'Confirmed TB NOT on treatment') GROUP BY fct.patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.confirmed_tb_on_treatment(patient_list, start_date, end_date)
    registered = []
    patient_ids = []

    (patient_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table fct
        INNER JOIN flat_table2 ft2 on ft2.patient_id = fct.patient_id
      WHERE fct.date_enrolled <= '#{end_date}'
      AND fct.date_enrolled <> '0000-00-00'
      AND ft2.visit_date = (SELECT MAX(visit_date) FROM flat_table2 WHERE patient_id = fct.patient_id AND visit_date <= '#{end_date}' AND tb_status IS NOT NULL)
      AND fct.patient_id IN (#{patient_ids.join(',')})
      AND ft2.tb_status = 'Confirmed TB on treatment' GROUP BY fct.patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.unknown_tb_status(patient_list, start_date, end_date)
    registered = []
    patient_ids = []

    (patient_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table fct
        INNER JOIN flat_table2 ft2 on ft2.patient_id = fct.patient_id
      WHERE fct.date_enrolled <= '#{end_date}'
      AND fct.date_enrolled <> '0000-00-00'
      AND ft2.visit_date = (SELECT MAX(visit_date) FROM flat_table2 WHERE patient_id = fct.patient_id AND visit_date <= '#{end_date}' AND tb_status IS NOT NULL)
      AND fct.patient_id IN (#{patient_ids.join(',')})
      AND ft2.tb_status = 'Unknown' GROUP BY fct.patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end
  end

  def self.total_patients_with_side_effects(patients_alive_and_on_art, start_date, end_date)
    patient_ids = []; results = []; patients_with_unknown_side_effects = []

    (self.unknown_side_effects(patients_alive_and_on_art, start_date, end_date) || []).each do |aPatient|
      patients_with_unknown_side_effects << aPatient['person_id'].to_i
    end
    patients_with_unknown_side_effects = [0] if patients_with_unknown_side_effects.blank?

    (patients_alive_and_on_art || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?

    malawi_art_side_effects =  ActiveRecord::Base.connection.select_all <<EOF
          SELECT ft2.patient_id, ft2.visit_date, ft2.side_effects_present, ft2.side_effects_present_enc_id
          FROM flat_cohort_table fct 
            INNER JOIN flat_table2 ft2 ON ft2.patient_id = fct.patient_id
          WHERE ft2.side_effects_present = 'Yes'
          AND (ft2.patient_id IN (#{patient_ids.join(',')}) 
          AND ft2.patient_id NOT IN (#{patients_with_unknown_side_effects.join(',')}))
          AND ft2.visit_date <= '#{end_date}'
          AND ft2.visit_date = (SELECT max(f2.visit_date) FROM flat_table2 f2
                            WHERE f2.side_effects_present IS NOT NULL
                            AND f2.patient_id = ft2.patient_id
                            AND f2.visit_date <= '#{end_date}')
          AND ft2.visit_date != fct.earliest_start_date;
EOF
    (malawi_art_side_effects || []).each do |row|
      results << row['patient_id']
    end
    return results
  end

  def self.total_patients_without_side_effects(patients_alive_and_or_art, patients_with_side_effects, unknown_side_effects)
    patient_ids = []; unknown_side_effects_patients = []; with_side_effects = []; result = []

    (patients_alive_and_or_art || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    #get all patients with side effects
    (patients_with_side_effects || []).each do |row|
      with_side_effects << row.to_i
    end

    #get all patients with side effects
    (unknown_side_effects || []).each do |row|
      unknown_side_effects_patients << row['person_id'].to_i
    end

    #get all patients with unknown_side_effects
    result = patient_ids - (with_side_effects + unknown_side_effects_patients)
    return result
  end

  def self.cal_regimem_category(patient_list, end_date)
    regimens = []

    patient_ids = []

    (patient_list || []).each do |row|
      patient_ids << row['patient_id'].to_i
    end

    return [] if patient_ids.blank?

    data = ActiveRecord::Base.connection.select_all <<EOF
      SELECT t.patient_id, regimen_category_dispensed, regimen_category_treatment, regimen_category, visit_date
      FROM flat_table2 t
      WHERE t.patient_id IN (#{patient_ids.join(', ')})
      AND t.visit_date = (SELECT max(visit_date) FROM flat_table2 f where t.patient_id = f.patient_id AND DATE(f.visit_date) <= '#{end_date}' 
                           AND (regimen_category IS NOT NULL));
EOF

    current_cohort_regimens = [
      "0P", "2P","4P","9P","11P","0A","2A","4A",
      "5A","6A","7A","8A","9A","10A","11A","12A"
    ]

    (data || []).each do |regimen_attr|
        regimen = regimen_attr['regimen_category']
        regimen = 'unknown_regimen' if regimen.blank? || regimen == 'Unknown' ||  !current_cohort_regimens.include?(regimen)
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
    data = ActiveRecord::Base.connection.select_all <<EOF
      SELECT patient_id, patient_died_in(fct.patient_id, po.cum_outcome, fct.date_enrolled) died_in
      FROM flat_cohort_table fct
        INNER JOIN temp_flat_tables_patient_outcomes po USING(patient_id)
      WHERE po.cum_outcome = 'Patient died'
      HAVING died_in = '#{month_str}';
EOF


    (data || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.total_alive_and_on_art(outcome, end_date)
    registered = []

    total_alive_and_on_art = ActiveRecord::Base.connection.select_all <<EOF
    SELECT patient_id, cum_outcome
    FROM temp_flat_tables_patient_outcomes
    WHERE cum_outcome = 'On antiretrovirals'
EOF
    (total_alive_and_on_art || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.defaulted(outcome, end_date)
    registered = []

    total_alive_and_on_art = ActiveRecord::Base.connection.select_all <<EOF
            SELECT patient_id, cum_outcome
            FROM temp_flat_tables_patient_outcomes
            WHERE cum_outcome = 'Defaulted'
EOF
    (total_alive_and_on_art || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.died_total(outcome, end_date)
    registered = []

    total_alive_and_on_art = ActiveRecord::Base.connection.select_all <<EOF
        SELECT patient_id, cum_outcome
        FROM temp_flat_tables_patient_outcomes
        WHERE cum_outcome = 'Patient died'
EOF
    (total_alive_and_on_art || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.stopped_art(outcome, end_date)
    registered = []

    total_alive_and_on_art = ActiveRecord::Base.connection.select_all <<EOF
          SELECT patient_id, cum_outcome
          FROM temp_flat_tables_patient_outcomes
          WHERE cum_outcome = 'Treatment stopped'
EOF
    (total_alive_and_on_art || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.transfered_out(outcome, end_date)
    registered = []

    total_alive_and_on_art = ActiveRecord::Base.connection.select_all <<EOF
    SELECT patient_id, cum_outcome
    FROM temp_flat_tables_patient_outcomes
    WHERE cum_outcome = 'Patient transferred out'
EOF
    (total_alive_and_on_art || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.unknown_outcome(outcome, end_date)
    registered = []

    total_alive_and_on_art = ActiveRecord::Base.connection.select_all <<EOF
        SELECT patient_id, cum_outcome
        FROM temp_flat_tables_patient_outcomes
        WHERE cum_outcome = 'Unknown'
EOF
    (total_alive_and_on_art || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.update_cum_outcome(end_date)
#=begin
      ActiveRecord::Base.connection.execute <<EOF
        DROP TABLE IF EXISTS `temp_flat_tables_patient_outcomes`;
EOF

      ActiveRecord::Base.connection.execute <<EOF
        CREATE TABLE temp_flat_tables_patient_outcomes
          SELECT patient_id, patient_outcome(patient_id, '#{end_date} 23:59:59') cum_outcome
        FROM flat_cohort_table
        WHERE date_enrolled <= '#{end_date}' AND date_enrolled <> '0000-00-00';
EOF
#=end
  end

  def self.kaposis_sarcoma(start_date, end_date)
    #KAPOSIS SARCOMA
    registered = []

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND (who_stages_criteria_present = 'Kaposis sarcoma' OR kaposis_sarcoma = 'Yes')
      AND DATE(kaposis_sarcoma_v_date) <= DATE(date_enrolled)
      GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.current_episode_of_tb(start_date, end_date)
    #CURRENT EPISODE OF TB
    registered = []

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND (pulmonary_tuberculosis = 'Yes'
          OR extrapulmonary_tuberculosis = 'Yes'
          OR who_stages_criteria_present IN ('EXTRAPULMONARY TUBERCULOSIS (EPTB)', 'PULMONARY TUBERCULOSIS', 'PULMONARY TUBERCULOSIS (CURRENT)'))
      AND (DATE(pulmonary_tuberculosis_v_date) <= DATE(date_enrolled) OR DATE(extrapulmonary_tuberculosis_v_date) <= DATE(date_enrolled))
     GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end
  end

  def self.tb_within_the_last_two_years(patients_with_current_tb ,start_date, end_date)
    #Pulmonary tuberculosis within the last 2 years
    registered = []
    
    patients_with_current_tb_episode = []
    (patients_with_current_tb || []).each do |patient|
      patients_with_current_tb_episode << patient['patient_id'].to_i
    end

    patients_with_current_tb_episode = [0] if patients_with_current_tb_episode.blank?

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND patient_id NOT IN (#{patients_with_current_tb_episode.join(',')})
      AND (pulmonary_tuberculosis_last_2_years = 'Yes'
          OR who_stages_criteria_present IN ('Pulmonary tuberculosis within the last 2 years', 'Ptb within the past two years'))
      AND (DATE(pulmonary_tuberculosis_last_2_years_v_date) <= DATE(date_enrolled) OR DATE(who_stages_criteria_present_v_date) <= DATE(date_enrolled))
     GROUP BY patient_id;
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
#----------------------------------------------------------------reworked reason for starting
  def self.children_12_23_months(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND reason_for_starting = 'HIV Infected' GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.unknown_other_reason_outside_guidelines(start_date, end_date)
    unknown_reason_registered = []; other_unknown_reason_reg = []
    revised_art_guidelines_date = '2016-04-01'.to_date

    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND reason_for_starting IN  ('Unknown', 'None') GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      unknown_reason_registered << patient
    end

    if start_date.to_date < revised_art_guidelines_date.to_date
      end_date = revised_art_guidelines_date

      other_uknown_reason_patients = ActiveRecord::Base.connection.select_all <<EOF
        SELECT * FROM flat_cohort_table
        WHERE reason_for_starting IN ('WHO stage II adult', 'WHO stage II adults', 'WHO stage II peds', 'WHO stage 2', 'WHO stage I adult', 'WHO stage I peds', 'WHO stage 1', 'LYMPHOCYTE COUNT BELOW THRESHOLD WITH WHO STAGE 1', 'LYMPHOCYTE COUNT BELOW THRESHOLD WITH WHO STAGE 2', 'LYMPHOCYTES')
        AND date_enrolled <> '0000-00-00'
        AND date_enrolled BETWEEN '#{start_date}' AND '#{end_date}' GROUP BY patient_id;
EOF
    end

    (other_uknown_reason_patients || []).each do |patient|
      other_unknown_reason_reg << patient
    end

    return unknown_reason_registered + other_unknown_reason_reg
  end

  def self.who_stage_four(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND reason_for_starting IN ('WHO stage IV adult', 'WHO stage IV peds', 'WHO stage 4') GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.who_stage_three(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
    SELECT * FROM flat_cohort_table t
    WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
    AND date_enrolled <> '0000-00-00'
    AND reason_for_starting IN ('WHO stage III adult', 'WHO stage III peds', 'WHO stage 3') GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.pregnant_women(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND reason_for_starting IN ('Patient pregnant', 'Patient pregnant at initiation')  GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.breastfeeding_mothers(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND reason_for_starting IN ('Currently breastfeeding child', 'Breastfeeding')  GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.asymptomatic(start_date, end_date)
    asy_registered = []; other_asy_registered = []
    revised_art_guidelines_date = '2016-04-01'.to_date

    asymptomatic_patients = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND reason_for_starting = 'ASYMPTOMATIC'  GROUP BY patient_id;
EOF

    (asymptomatic_patients || []).each do |patient|
      asy_registered << patient
    end

    #raise "#{start_date}, #{revised_art_guidelines_date}"
    if start_date.to_date >= revised_art_guidelines_date.to_date
      start_date = start_date
    else
      start_date = revised_art_guidelines_date
    end

    other_asymptomatic_patients = ActiveRecord::Base.connection.select_all <<EOF
          SELECT patient_id, date_enrolled, reason_for_starting
          FROM flat_cohort_table
          WHERE reason_for_starting IN ('WHO stage II adult', 'WHO stage II adults', 'WHO stage II peds', 'WHO stage 2', 'WHO stage I adult', 'WHO stage I peds', 'WHO stage 1', 'LYMPHOCYTE COUNT BELOW THRESHOLD WITH WHO STAGE 1', 'LYMPHOCYTE COUNT BELOW THRESHOLD WITH WHO STAGE 2', 'LYMPHOCYTES')
          AND date_enrolled <> '0000-00-00'
          AND date_enrolled BETWEEN '#{start_date}' and '#{end_date}' GROUP BY patient_id;
EOF

    (other_asymptomatic_patients || []).each do |patient|
      other_asy_registered << patient
    end

    return asy_registered + other_asymptomatic_patients
  end

  def self.who_stage_two(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND reason_for_starting LIKE '%CD4 COUNT%' GROUP BY patient_id;
EOF
    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.confirmed_hiv_infection_in_infants_pcr(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND (reason_for_starting LIKE '%HIV PCR%' OR reason_for_starting LIKE '%HIV DNA%')
      GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

  end

  def self.presumed_severe_hiv_disease_in_infants(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
      AND reason_for_starting like '%Presumed severe%' GROUP BY patient_id;
EOF
    (total_registered || []).each do |patient|
      registered << patient
    end

  end
#----------------------------------------------------------------reworked reason for starting
  def self.unknown_age(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
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
      SELECT * FROM flat_cohort_table
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
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
      SELECT * FROM flat_cohort_table
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
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
      SELECT * FROM flat_cohort_table
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00'
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
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND (gender = 'F' OR gender = 'Female')
      AND t.patient_id NOT IN(#{pregnant_women_ids.join(',')})
      AND date_enrolled <> '0000-00-00'
      GROUP BY patient_id;
EOF

    (data || []).each do |patient|
      registered << patient
    end

    return registered
  end
#---to redo
  def self.pregnant_females_all_ages(start_date, end_date)
    registered = [] ; patient_id_plus_date_enrolled = []
    transfer_ins_preg_women = []; pregnant_females = []
    all_pregnant_females = []


    #(patient_id_plus_date_enrolled || []).each do |patient_id, date_enrolled|
    registered = ActiveRecord::Base.connection.select_all <<EOF
              SELECT t.* FROM temp_patient_pregnant t
                INNER JOIN flat_cohort_table fct ON fct.patient_id = t.patient_id
              WHERE (fct.gender = 'F' OR fct.gender = 'Female')
              AND fct.date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
              AND date_enrolled <> '0000-00-00'
              AND t.patient_pregnant = 'Yes'
              AND DATE(t.visit_date) = DATE(fct.earliest_start_date)
              GROUP BY t.patient_id;
EOF

    pregnant_at_initiation = ActiveRecord::Base.connection.select_all <<EOF
                    SELECT patient_id, date_enrolled, earliest_start_date, reason_for_starting
                    FROM flat_cohort_table
                    WHERE reason_for_starting = 'Patient pregnant'
                    AND gender = 'F'
                    AND (date_enrolled BETWEEN '#{start_date}' AND '#{end_date}');
EOF
    pregnant_at_initiation_ids = []
    (pregnant_at_initiation || []).each do |patient|
      pregnant_at_initiation_ids << patient['patient_id'].to_i
    end

    if pregnant_at_initiation_ids.blank?
      pregnant_at_initiation_ids = [0]
    end

    transfer_ins_women = ActiveRecord::Base.connection.select_all <<EOF
          SELECT patient_id FROM flat_cohort_table
          WHERE date_enrolled  BETWEEN '#{start_date}' AND '#{end_date}'
          AND (gender = 'F' OR gender = 'Female')
          AND DATE(date_enrolled) != DATE(earliest_start_date)
          AND date_enrolled <> '0000-00-00'
          AND patient_id IN (#{pregnant_at_initiation_ids.join(',')})
          AND patient_re_initiated != 'Re-initiated'
          GROUP BY patient_id
EOF

    (transfer_ins_women || []).each do |patient|
      if patient['patient_id'].to_i != 0
        transfer_ins_preg_women << patient['patient_id'].to_i
      end
    end

    (registered || []).each do |patient|
      if patient['patient_id'].to_i != 0
        pregnant_females << patient['patient_id'].to_i
      end
    end
 
    all_pregnant_females = (pregnant_females + transfer_ins_preg_women).uniq
    return all_pregnant_females
  end

  def self.males(start_date, end_date)
    registered = []
    data = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table t
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND (gender = 'Male' OR gender = 'M')
      AND date_enrolled <> '0000-00-00'
      GROUP BY patient_id;
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
          SELECT patient_id FROM flat_cohort_table
          WHERE date_enrolled  BETWEEN '#{start_date}' AND '#{end_date}'
          AND DATE(date_enrolled) != DATE(earliest_start_date)
          AND date_enrolled <> '0000-00-00'
          AND patient_re_initiated != 'Re-initiated'
          GROUP BY patient_id
EOF

    (data || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.re_initiated_on_art(start_date, end_date)
    registered = []
    data = ActiveRecord::Base.connection.select_all <<EOF
            SELECT patient_id, patient_re_initiated FROM flat_cohort_table
            WHERE date_enrolled  BETWEEN '#{start_date}' AND '#{end_date}'
            AND DATE(date_enrolled) != DATE(earliest_start_date)
            AND date_enrolled <> '0000-00-00'
            AND patient_re_initiated = 'Re-initiated'
            GROUP BY patient_id;
EOF

    (data || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.initiated_on_art_first_time(start_date, end_date)
    registered = []
    data = ActiveRecord::Base.connection.select_all <<EOF
      SELECT * FROM flat_cohort_table
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND DATE(date_enrolled) = DATE(earliest_start_date)
      AND date_enrolled <> '0000-00-00'
      GROUP BY patient_id;
EOF

    (data || []).each do |patient|
      registered << patient
    end

    return registered
  end

  def self.get_cum_start_date
    cum_start_date = ActiveRecord::Base.connection.select_value <<EOF
      SELECT MIN(date_enrolled) FROM flat_cohort_table WHERE date_enrolled <> '0000-00-00';
EOF

    return cum_start_date.to_date rescue nil
  end

  def self.total_registered(start_date, end_date)
    registered = []
    total_registered = ActiveRecord::Base.connection.select_all <<EOF
      SELECT patient_id, earliest_start_date, date_enrolled, birthdate, death_date, age_at_initiation
      FROM flat_cohort_table
      WHERE date_enrolled BETWEEN '#{start_date}' AND '#{end_date}'
      AND date_enrolled <> '0000-00-00' GROUP BY patient_id;
EOF

    (total_registered || []).each do |patient|
      registered << patient
    end

    return registered
  end


end
