
class ProgramWorkflowState < ActiveRecord::Base
  self.table_name = "program_workflow_state"
  self.primary_key = "program_workflow_state_id"
  include Openmrs
  belongs_to :program_workflow,-> {where(retired: 0)}, optional: true
  belongs_to :concept, ->{where(retired: 0)}, optional: true

  def self.find_state(state_id)
    self.find_by_sql(["SELECT * FROM `program_workflow_state` WHERE (`program_workflow_state`.`program_workflow_state_id` = ?)", state_id]).first
  end
end