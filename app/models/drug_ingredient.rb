require "composite_primary_keys"
class DrugIngredient < ActiveRecord::Base
  self.table_name = "drug_ingredient"
  belongs_to :concept, foreign_key: :concept_id
  belongs_to :ingredient, foreign_key: :ingredient_id, class_name: :Concept
  self.primary_keys = :ingredient_id, :concept_id

  def to_fixture_name
    "#{concept.to_fixture_name}_contains_#{ingredient.to_fixture_name}"
  end
end
