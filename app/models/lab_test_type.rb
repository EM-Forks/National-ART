	class LabTestType < HealthdataConnection
	  self.table_name = "codes_TestType"
    
    def self.test_name(test_type)
      return LabTestType.where(["TESTTYPE=?",test_type.to_i]).first.TestName rescue nil
    end 
    
    def self.test_type_by_name(test_type)
      panel_id = LabTestType.where(["TestName=?",test_type]).first.Panel_ID rescue nil
      return LabPanel.test_name(panel_id).to_s rescue nil
    end 

    def self.available_test
      self.all.map{|test|test.TestName}
    end
  end  
