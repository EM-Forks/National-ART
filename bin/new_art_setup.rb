=begin
    Author: mangochiman
    Purpose:
          1. Simplify the process of setting up the new ART
    Start Date: 26/January/2017
    End Date: ??/??/????
=end
# quit unless our script gets one command line arguments

def easy_art_setup
  environment = ""
  if Rails.env.development?
    environment = "development"
  end
  if Rails.env.production?
    environment = "production"
  end
 if Rails.env.test?
   environment = "test"
 end
  puts "===You are running on #{environment} environment for database setup=================>"
  
  puts "================Mysql database commands now launched.Please wait====================>"
  username = YAML::load_file('config/database.yml')[environment]['username']
  password = YAML::load_file('config/database.yml')[environment]['password']
  database = YAML::load_file('config/database.yml')[environment]['database']
  host = YAML::load_file('config/database.yml')[environment]['host']

  `echo "DROP DATABASE #{database};" | mysql --host=$HOST --user=#{username} --password=#{password}`
  `echo "CREATE DATABASE #{database};" | mysql --host=$HOST --user=$USERNAME --password=#{password}`


  `mysql -h #{host} -u #{username} -p#{password} #{database} < db/bart2_views_schema_additions.sql`
  `mysql -h #{host} -u #{username} -p#{password} #{database} < db/openmrs_metadata_1_7.sql`
  `mysql -h #{host} -u #{username} -p#{password} #{database} < db/revised_regimens.sql`
  `rake db:migrate`
  `mysql -h #{host} -u #{username} -p#{password} #{database} < db/drug_order_barcodes.sql`
  
  `mysql --user=#{username} --password=#{password} #{database} < db/openmrs_1_7_2_concept_server_full_db.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/schema_bart2_additions.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/defaults.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/malawi_regions.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/mysql_functions.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/drug_ingredient.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/pharmacy.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/national_id.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/weight_for_heights.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/data/${SITE}/${SITE}.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/data/${SITE}/tasks.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/moh_regimens_only.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/regimen_indexes.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/retrospective_station_entries.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/openmrs_metadata_1_7.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/create_dde_server_connection.sql`
  `mysql --user=#{username} --password=#{password} #{database} < db/underlined_diseases_concept_metadata.sql`
  `mysql  --user=#{username} --password=#{password} #{database} < db/initial_setup/modular_tables.sql`
  `mysql  --user=#{username} --password=#{password} #{database} < db/migrate/create_weight_height_for_ages.sql`
  `mysql  --user=#{username} --password=#{password} #{database} < db/migrate/insert_weight_for_ages.sql`
  `mysql  --user=#{username} --password=#{password} #{database} < db/openmrs_metadata_1_7.sql`
  `mysql  --user=#{username} --password=#{password} #{database} < db/initial_setup/regimens.sql`

  create_reinitiated_check_view
  puts "==========================Database setup successfully completed======================>"
end

def create_reinitiated_check_view
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
end

easy_art_setup
