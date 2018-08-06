class TableLabResult < HealthdataConnection
  self.table_name = "tblLabResults"

  def self.lab_results
    self.where("TestResult IS NOT NULL")
  end
end
