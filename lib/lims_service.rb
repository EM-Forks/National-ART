module LimsService
	include CoreService
	require 'bean'
	require 'json'
	require 'rest_client'

  def self.lims_settings
    data = {}
    lims_ip = GlobalProperty.find_by_property('lims.address').property_value rescue "localhost"
    lims_port = GlobalProperty.find_by_property('lims.port').property_value rescue "3009"
    lims_username = GlobalProperty.find_by_property('lims.username').property_value rescue "admin"
    lims_password = GlobalProperty.find_by_property('lims.password').property_value rescue "admin"

    data["lims_ip"] = lims_ip
    data["lims_port"] = lims_port
    data["lims_username"] = lims_username
    data["lims_password"] = lims_password
    data["lims_address"] = "http://#{lims_ip}:#{lims_password}"

    return data
  end

  def self.initial_lims_authentication_token
    lims_username = lims_settings["lims_username"]
    lims_password = lims_settings["lims_password"]

    lims_address = "#{lims_settings["lims_address"]}/authenticate/#{lims_username}/#{lims_password}"
    received_params = RestClient.get(lims_address)
    lims_token = JSON.parse(received_params)["data"]["token"]

    return lims_token
  end

  def self.add_lims_user(params)
    limis_token = ""

    passed_params = {
      :partner => "BHT",
      :app_name => "NART",
      :location => "Lilongwe",
      :password => params[:password],
      :username => params[:username]
    }

    lims_address = "#{lims_settings["lims_address"]}/create_user/#{limis_token}"
    headers = {:content_type => "json" }
    received_params = RestClient.post(lims_address, passed_params.to_json, headers)
    data = JSON.parse(received_params)
    return data
  end
  
  def self.verify_lims_token_authenticity
    lims_token = ""

    lims_address = "#{lims_settings["lims_address"]}/check_token_validity/#{lims_token}"
    received_params = RestClient.get(lims_address)
    lims_status = JSON.parse(received_params)["status"]

    return lims_status
  end

  def self.create_lims_order(params)
    #/v1/create_order/:token
    lims_token = ""
    lims_address = "#{lims_settings["lims_address"]}/v1/create_order/#{lims_token}"
    passed_params = {
      :district => params[:district],
      :health_facility_name => params[:health_facility_name],
      :first_name => params[:first_name],
      :last_name => params[:last_name],
      :middle_name => params[:middle_name],
      :gender => params[:gender],
      :national_patient_id => params[:national_patient_id],
      :reason_for_test => params[:reason_for_test],
      :sample_collector_last_name => params[:sample_collector_last_name],
      :sample_collector_phone_number => params[:sample_collector_phone_number],
      :sample_collector_id => params[:sample_collector_id],
      :sample_order_location => params[:sample_order_location],
      :requesting_clinician => params[:requesting_clinician],
      :sample_type => params[:sample_type],
      :date_sample_drawn => params[:date_sample_drawn],
      :tests => params[:tests],
      :sample_priority => params[:sample_priority],
      :target_lab => params[:target_lab],
      :art_start_date => params[:art_start_date]
    }

    headers = {:content_type => "json" }
    received_params = RestClient.post(lims_address, passed_params.to_json, headers)
    data = JSON.parse(received_params)
    return data
  end



  def self.search_lims_by_identifier(identifier, lims_token)
    lims_address = "#{lims_settings["lims_address"]}/v1/search_by_identifier/#{identifier}/#{lims_token}"
    received_params = RestClient.get(lims_address){|response, request, result|response}
    received_params = "{}" if received_params.blank?
    results = JSON.parse(received_params){|response, request, result|response}
    return results
  end

  def self.search_lims_by_name_and_gender(params, token)
    return [] if params[:given_name].blank?
    gender = {'M' => 'Male', 'F' => 'Female'}
    passed_params = {
      :given_name => params[:given_name],
      :family_name => params[:family_name],
      :gender => gender[params[:gender].upcase],
      :token => token
    }

    lims_address = "#{lims_settings["lims_address"]}/v1/search_by_name_and_gender"
    headers = {:content_type => "json" }
    received_params = RestClient.post(lims_address, passed_params.to_json, headers)
    results = JSON.parse(received_params)["data"]["hits"] rescue {}
    return results
  end

  def self.lims_advanced_search(params)
    passed_params = {
      :given_name => params[:given_name],
      :family_name => params[:family_name],
      :gender => params[:gender],
      :birthdate => params[:birthdate],
      :home_district => params[:home_district],
      :token => self.lims_authentication_token
    }

    lims_address = "#{lims_settings["lims_address"]}/v1/search_by_name_and_gender"
    received_params = RestClient.post(lims_address, passed_params)
    results = JSON.parse(received_params)["data"]["hits"]
    return results
  end

  def self.void_lims_patient(identifier)
    lims_token = self.lims_authentication_token
    lims_address = "#{lims_settings["lims_address"]}/v1/void_patient/#{identifier}/#{lims_token}"
    received_params = RestClient.get(lims_address)
    status = JSON.parse(received_params)["status"]
    return status
  end

  def self.update_lims_patient(person, lims_token)
    passed_params = self.generate_lims_data_to_be_updated(person, lims_token)
    lims_address = "#{lims_settings["lims_address"]}/v1/update_patient"
    headers = {:content_type => "json" }
    received_params = RestClient.post(lims_address, passed_params.to_json, headers)
    results = JSON.parse(received_params)
    return results
  end

  def self.add_lims_patient(params, lims_token)
    lims_address = "#{lims_settings["lims_address"]}/v1/add_patient"
    gender = {'M' => 'Male', 'F' => 'Female'}
    person = Person.new
    birthdate = "#{params["person"]['birth_year']}-#{params["person"]['birth_month']}-#{params["person"]['birth_day']}"
    birthdate = birthdate.to_date.strftime("%Y-%m-%d") rescue birthdate

    if params["person"]["birth_year"] == "Unknown"
      self.set_birthdate_by_age(person, params["person"]['age_estimate'], Date.today)
    else
      self.set_birthdate(person, params["person"]["birth_year"], params["person"]["birth_month"], params["person"]["birth_day"])
    end

    unless params["person"]['birthdate_estimated'].blank?
      person.birthdate_estimated = params["person"]['birthdate_estimated'].to_i
    end

    passed_params = {
      "family_name" => params["person"]["names"]["family_name"],
      "given_name" => params["person"]["names"]["given_name"],
      "middle_name" => params["person"]["names"]["middle_name"],
      "gender" => gender[params["person"]["gender"]],
      "attributes" => {},
      "birthdate" => person.birthdate.to_date.strftime("%Y-%m-%d"),
      "identifiers" => {},
      "birthdate_estimated" => (person.birthdate_estimated.to_i == 1),
      "current_residence" => params["person"]["addresses"]["city_village"],
      "current_village" => params["person"]["addresses"]["city_village"],
      "current_ta" => params["filter"]["t_a"],
      "current_district" => params["person"]["addresses"]["state_province"],

      "home_village" => params["person"]["addresses"]["neighborhood_cell"],
      "home_ta" => params["person"]["addresses"]["county_district"],
      "home_district" => params["person"]["addresses"]["address2"],
      "token" => lims_token
    }

    headers = {:content_type => "json" }
    received_params = RestClient.put(lims_address, passed_params.to_json, headers){|response, request, result|response}
    results = JSON.parse(received_params)
    return results
  end

  def self.add_lims_conflict_patient(lims_return_path, params, lims_token)
    lims_address = "#{lims_settings["lims_address"]}#{lims_return_path}"
    gender = {'M' => 'Male', 'F' => 'Female'}
    person = Person.new
    birthdate = "#{params["person"]['birth_year']}-#{params["person"]['birth_month']}-#{params["person"]['birth_day']}"
    birthdate = birthdate.to_date.strftime("%Y-%m-%d") rescue birthdate

    if params["person"]["birth_year"] == "Unknown"
      self.set_birthdate_by_age(person, params["person"]['age_estimate'], Date.today)
    else
      self.set_birthdate(person, params["person"]["birth_year"], params["person"]["birth_month"], params["person"]["birth_day"])
    end

    unless params["person"]['birthdate_estimated'].blank?
      person.birthdate_estimated = params["person"]['birthdate_estimated'].to_i
    end

    passed_params = {
      "family_name" => params["person"]["names"]["family_name"],
      "given_name" => params["person"]["names"]["given_name"],
      "middle_name" => params["person"]["names"]["middle_name"],
      "gender" => gender[params["person"]["gender"]],
      "attributes" => {},
      "birthdate" => person.birthdate.to_date.strftime("%Y-%m-%d"),
      "identifiers" => {},
      "birthdate_estimated" => (person.birthdate_estimated.to_i == 1),
      "current_residence" => (params["person"]["addresses"]["city_village"] rescue 'Other'),
      "current_village" => (params["person"]["addresses"]["city_village"] rescue 'Other'),
      "current_ta" => (params["filter"]["t_a"] rescue 'N/A'),
      "current_district" => (params["person"]["addresses"]["state_province"] rescue 'Other'),

      "home_village" => (params["person"]["addresses"]["neighborhood_cell"] rescue 'Other'),
      "home_ta" => (params["person"]["addresses"]["county_district"] rescue 'Other'),
      "home_district" => (params["person"]["addresses"]["address2"] rescue 'Other'),
      "token" => lims_token
    }

    headers = {:content_type => "json" }
    received_params = RestClient.put(lims_address, passed_params.to_json, headers){|response, request, result|response}
    results = JSON.parse(received_params)
    return results
  end


end
