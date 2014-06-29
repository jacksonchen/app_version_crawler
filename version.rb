class Version
  attr_reader :name
  attr_accessor :title, :creator, :update_date,
  :description, :size, :version,
  :what_is_new
  
  def initialize(name)
    @name = name
  end
  
end