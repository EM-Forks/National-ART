class MohRegimen < ActiveRecord::Base
  self.table_name =  "moh_regimens"
  self.primary_key = "regimen_id"

  has_many :ingredients, foreign_key: :regimen_id
  has_many :ingredients, class_name: :MohRegimenIngredient, foreign_key: :regimen_id

end
