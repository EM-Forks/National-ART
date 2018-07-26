class PersonNameCode < ActiveRecord::Base
  before_save :before_save
  before_create :before_create

  self.table_name = "person_name_code"
  self.primary_key =  "person_name_code_id"

  include Openmrs
  belongs_to :person_name, ->{where(voided:0)}

  def before_save

    self.changed_by = User.current.id if self.has_attribute?("changed_by") and User.current != nil

    self.changed_by = User.first if self.has_attribute?("changed_by") and User.current.nil?

    self.date_changed = Time.now if self.has_attribute?("date_changed")
  end

  def before_create

    if !Person.migrated_datetime.to_s.empty?
      self.location_id = Person.migrated_location if self.has_attribute?("location_id")
      self.creator = Person.migrated_creator if self.has_attribute?("creator")
      self.date_created = Person.migrated_datetime if self.has_attribute?("date_created")
    else
      self.location_id = Location.current_health_center.id if self.has_attribute?("location_id") and (self.location_id.blank? || self.location_id == 0) and Location.current_health_center != nil
      self.creator = User.current.id if self.has_attribute?("creator") and (self.creator.blank? || self.creator == 0)and User.current != nil
      self.date_created = Time.now if self.has_attribute?("date_created")
    end

    self.uuid = ActiveRecord::Base.connection.select_one("SELECT UUID() as uuid")['uuid'] if self.has_attribute?("uuid")
  end
  
  def self.rebuild_person_name_codes
    PersonNameCode.delete_all
    names = PersonName.find(:all)
    names.each {|name|
      PersonNameCode.create(
        :person_name_id => name.person_name_id,
        :given_name_code => (name.given_name || '').soundex,
        :middle_name_code => (name.middle_name || '').soundex,
        :family_name_code => (name.family_name || '').soundex,
        :family_name2_code => (name.family_name2 || '').soundex,
        :family_name_suffix_code => (name.family_name_suffix || '').soundex
      ) unless (name.voided? || name.person.nil?|| name.person.voided? || name.person.patient.nil?|| name.person.patient.voided?)
    }
  end

  # Find all of the matches for this code  
  # When we order them we want to prioritize:
  #   - Items where the search text matches the actual name ("Mary" versus "Mari")
  #   - Items where the actual soundex starts with the soundex for the search text ("M4" versus "M6")
  #   - Items where the length of the soundex matches the length of the soundex for the search text ("M4" versus "M42")
  #     - Worry about "M42" versus "M4"
  #       LENGTH(#{field_name}_code) - LENGTH(?) ASC,
  #   - Popularity of the search text
  #   - Search text alphabetized
  def self.find_most_common(field_name, search_string)
    soundex = (search_string || '').soundex
    self.find_by_sql([
      "SELECT DISTINCT #{field_name} AS #{field_name}, person_name.person_name_id AS id
       FROM person_name_code \
       INNER JOIN person_name ON person_name_code.person_name_id = person_name.person_name_id \
       INNER JOIN person ON person.person_id = person_name.person_id \
       WHERE person.voided = 0 AND person_name.voided = 0 AND (#{field_name}_code LIKE ? \
       OR person_name.#{field_name} LIKE ?) GROUP BY #{field_name} \
       ORDER BY \
         CASE INSTR(#{field_name},?) WHEN 0 THEN 9999 ELSE INSTR(#{field_name},?) END ASC, \
         CASE INSTR(#{field_name}_code,?) WHEN 0 THEN 9999 ELSE INSTR(#{field_name}_code,?) END ASC, \
         ABS(LENGTH(#{field_name}_code) - LENGTH(?)) ASC,
         COUNT(#{field_name}) DESC,  \
         #{field_name} ASC \
       LIMIT 10",
       "#{soundex}%", "%#{search_string}%",search_string, search_string, soundex, soundex, soundex])
  end
end
