class MohRegimenIngredient < ActiveRecord::Base
  self.table_name = "moh_regimen_ingredient"
  self.primary_key = "ingredient_id"

  belongs_to :regimen, class_name: :MohRegimen, foreign_key: :regimen_id

  def self.get_moh_regimen_ingredient_min_max_weight(index, drug_id)
    i = MohRegimenIngredient.where(["drug_inventory_id = ? AND regimen_id = ?", drug_id, index]).first
    return [i.min_weight, i.max_weight] #unless i.blank?
  end

end
