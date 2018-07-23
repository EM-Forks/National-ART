class SessionsController < GenericSessionsController

 def set_session_var
  session[params[:key]] = params[:value]
  render :text => true
 end

 def location
    @login_wards = (CoreService.get_global_property_value('facility.login_wards')).split(',') rescue []
    if (CoreService.get_global_property_value('select_login_location').to_s == "true" rescue false)
      render :template => 'sessions/select_location'
    end

    @activate_drug_management = CoreService.get_global_property_value('activate.drug.management').to_s == "true" rescue false
  end
  
end
