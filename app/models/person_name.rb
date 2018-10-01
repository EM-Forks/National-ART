class PersonName < ActiveRecord::Base
  before_save :before_save
  before_create :before_create
  self.table_name = "person_name"
  self.primary_key = "person_name_id"
  include Openmrs
  belongs_to :person, ->{where(voided:0)},foreign_key: :person_id, optional: true
  has_one :person_name_code, foreign_key: :person_name_id # no default scope
  def before_save

    self.changed_by = User.current.id if self.has_attribute?("changed_by") and User.current != nil

    self.changed_by = User.first if self.has_attribute?("changed_by") and User.current.nil?

    self.date_changed = Time.now if self.has_attribute?("date_changed")

    self.build_person_name_code(
      :person_name_id => self.person_name_id,
      :given_name_code => (self.given_name || '').soundex,
      :middle_name_code => (self.middle_name || '').soundex,
      :family_name_code => (self.family_name || '').soundex,
      :family_name2_code => (self.family_name2 || '').soundex,
      :family_name_suffix_code => (self.family_name_suffix || '').soundex)
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

  def prepare_name_code
    self.build_person_name_code(
      :person_name_id => self.person_name_id,
      :given_name_code => (self.given_name || '').soundex,
      :middle_name_code => (self.middle_name || '').soundex,
      :family_name_code => (self.family_name || '').soundex,
      :family_name2_code => (self.family_name2 || '').soundex,
      :family_name_suffix_code => (self.family_name_suffix || '').soundex)
  end

  def self.search(field_name, search_string)
    return self.where(["#{field_name} LIKE (?)",
      "#{search_string}%"]).group("#{field_name}").limit(10)
  end

  # Looks for the most commonly used element in the database and sorts the results based on the first part of the string
  def self.find_most_common(field_name, search_string)
    return self.find_by_sql([
    "SELECT DISTINCT #{field_name} AS #{field_name}, #{self.primary_key} AS id \
     FROM person_name \
     INNER JOIN person ON person.person_id = person_name.person_id \
     WHERE person.voided = 0 AND person_name.voided = 0 AND #{field_name} LIKE ? \
     GROUP BY #{field_name} ORDER BY INSTR(#{field_name},\"#{search_string}\") ASC, COUNT(#{field_name}) DESC, #{field_name} ASC LIMIT 10", "%#{search_string}%"])
  end

end
