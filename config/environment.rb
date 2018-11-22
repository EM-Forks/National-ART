# Load the Rails application.
require_relative 'application'

# Initialize the Rails application.
Rails.application.initialize!

# Specifies gem version of Rails to use when vendor/rails is not present
RAILS_GEM_VERSION = '5.2.0' unless defined? RAILS_GEM_VERSION
ART_VERSION = "v3.7.9" #`git describe`.gsub("\n", "")

# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')
require 'pdfkit'

ART_SETTINGS = YAML.load_file(File.join(Rails.root, "config", "settings.yml"))[Rails.env] rescue nil

require 'will_paginate'
require 'fixtures'
require 'composite_primary_keys'
require 'has_many_through_association_extension'
require 'bantu_soundex'
require 'json'
require 'colorfy_strings'
require 'action_mailer'

ActiveSupport::Inflector.inflections do |inflect|
  inflect.irregular 'person_address', 'person_address'
  inflect.irregular 'obs', 'obs'
  inflect.irregular 'concept_class', 'concept_class'
end

healthdata = YAML.load(File.open(File.join(Rails.root, "config/database.yml"), "r"))['healthdata']
bart_one_data = YAML.load(File.open(File.join(Rails.root, "config/database.yml"), "r"))['migration']
#Lab.establish_connection(healthdata)
#LabTestType.establish_connection(healthdata)
#LabTestTable.establish_connection(healthdata)
#LabPanel.establish_connection(healthdata)
#LabParameter.establish_connection(healthdata)
#TableLabResultList.establish_connection(healthdata)
#TableLabResult.establish_connection(healthdata)
#LabSample.establish_connection(healthdata)

BartOneEncounter.establish_connection(bart_one_data) # added for migration
BartOneObservation.establish_connection(bart_one_data) # added for migration
BartOneDrugOrder.establish_connection(bart_one_data) # added for migration

class Mime::Type
  delegate :split, :to => :to_s
end

# Foreign key checks use a lot of resources but are useful during development
ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS=0") if ENV['RAILS_ENV'] != 'development'
require 'will_paginate'


