class StockManagementController < ApplicationController

  def new_deliveries
    encounter_type = PharmacyEncounterType.find_by_name('New deliveries')
    obs = Pharmacy.create(pharmacy_encounter_type: encounter_type.id,
      drug_id: params[:drug_id], value_numeric: (params[:total_tins].to_f * params[:pack_size].to_f).to_f,
      expiry_date: "#{params[:expiry_date]}/01".to_date.end_of_month, 
      encounter_date: params[:delivery_date].to_date, creator: User.current.id,
      value_text: params[:delivery_code], date_created: Time.now(), pack_size: params[:pack_size])

    
    recalculate_stock(obs.drug_id)

    render json: obs and return
  end


  private

  def recalculate_stock(drug_id)
    encounter_type = PharmacyEncounterType.find_by_name('New deliveries')

    total_delivered_sock = 0
    start_dates = []
    total_deliveries = Pharmacy.where(drug_id: drug_id, 
      pharmacy_encounter_type: encounter_type.id).select("value_numeric, pack_size, encounter_date")
    
    pack_size = 0

    (total_deliveries || []).each do |delivery|
      total_delivered_sock += delivery.value_numeric 
      start_dates << delivery.encounter_date
      pack_size = delivery.pack_size
    end

    start_date = start_dates.sort.first.to_date.strftime("%Y-%m-%d 00:00:00")

    drug_orders = DrugOrder.where("o.start_date BETWEEN (?) AND (?)", 
      start_date, Date.today.strftime("%Y-%m-%d 23:59:59")).joins("INNER JOIN orders o
      ON o.order_id = drug_order.order_id AND o.voided = 0").select("drug_order.*, o.start_date")

    total_dispensed_per_day = {}

    (drug_orders || []).each do |drug_order|
      if total_dispensed_per_day[drug_order.start_date.to_date].blank?
        total_dispensed_per_day[drug_order.start_date.to_date] = {
          currrent_stock: nil, total_dispensed: 0
        }
      end

      total_dispensed_per_day[drug_order.start_date.to_date][:total_dispensed] += (drug_order.quantity.to_f rescue 0)
    end

    (total_dispensed_per_day || {}).each do |date, data|
      if data[:total_dispensed] > 0
        stock_level = calculate_stock_levels(drug_id, start_date, date, pack_size, data[:total_dispensed])
      else
        stock_level = calculate_stock_levels(drug_id, start_date, date, pack_size, 0)
      end
      
      data[:currrent_stock] = stock_level
    end


  end

  def calculate_stock_levels(drug_id, start_date, end_date, pack_size, total_dispensed)
    start_date = start_date.to_date.strftime("%Y-%m-%d 00:00:00")
    end_date =  end_date.to_date.strftime("%Y-%m-%d 23:59:59")

    encounter_type = PharmacyEncounterType.find_by_name('New deliveries')
    obs = Pharmacy.where("pharmacy_encounter_type = ? AND drug_id = ? AND
      (encounter_date BETWEEN ? AND ?)", encounter_type.id, drug_id, start_date, end_date)

    total_pills = obs.sum(:value_numeric).to_f rescue 0
    currrent_stock = (total_pills.to_f - total_dispensed.to_f) rescue 0
   
    currrent_stock = 0 if currrent_stock < 0
    
    encounter_type = PharmacyEncounterType.find_by_name("Tins currently in stock")
    stock = Pharmacy.where("pharmacy_encounter_type = ? AND drug_id = ? AND
      (encounter_date = ?)", encounter_type.id, drug_id, end_date.to_date)


    if stock.blank?
      stock = Pharmacy.create(pharmacy_encounter_type: encounter_type.id,
        drug_id: drug_id, value_numeric: currrent_stock, pack_size: pack_size,
        encounter_date: end_date.to_date, creator: User.current.id, date_created: Time.now())
    else
      stock = stock.last
      stock.update_attributes(value_numeric: currrent_stock, date_changed: Time.now.to_date,
        changed_by: User.current.id, pack_size: pack_size)
    end
    
    return stock.value_numeric
  end

end
