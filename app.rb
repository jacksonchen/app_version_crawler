require File.expand_path('../jsonable.rb', __FILE__)


class App < JSONable
  attr_reader :name
  attr_accessor :title, :creator
  
  def initialize(name)
    @name = name
  end
  
end
