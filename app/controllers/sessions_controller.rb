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
=begin
    if (@activate_drug_management)
      @stock = {}
      drug_names = GenericDrugController.new.preformat_regimen
      drug_names.each do |drug_name|
        drug = Drug.find_by_name(drug_name)
        drug_pack_size = Pharmacy.pack_size(drug.id)
        current_stock = (Pharmacy.latest_drug_stock(drug.id)/drug_pack_size).to_i #In tins
        next unless (current_stock.to_i == 0)
        consumption_rate = Pharmacy.average_drug_consumption(drug.id)
        stock_out_days = ((current_stock * drug_pack_size)/consumption_rate).to_i rescue 0 #To avoid division by zero error when consumption_rate is zero
        estimated_stock_out_date = (Date.today + stock_out_days).strftime('%d-%b-%Y')
        estimated_stock_out_date = "(N/A)" if (consumption_rate.to_i <= 0)
        estimated_stock_out_date = "Stocked out" if (current_stock <= 0) #We don't want to estimate the stock out date if there is no stock available

        @stock[drug.id] = {}
        @stock[drug.id]["drug_name"] = drug.name
        @stock[drug.id]["current_stock"] = current_stock
        @stock[drug.id]["consumption_rate"] = consumption_rate.to_f.round(1)
        @stock[drug.id]["estimated_stock_out_date"] = estimated_stock_out_date
        @stock[drug.id]["drug_pack_size"] = drug_pack_size
      end
      @stock = @stock.sort_by{|drug_id, values|values["drug_name"]}
    end
=end
 end
end
