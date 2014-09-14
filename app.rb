require File.expand_path('../jsonable.rb', __FILE__)


class App < JSONable
  attr_reader :name
  attr_accessor :title, :creator, :description, :domain, :category

  def initialize(name)
    @name = name
  end

end

class Version < JSONable
  attr_reader :name
  attr_accessor :update_date,
  :size, :version,
  :what_is_new, :download_link

  def initialize(name)
    @name = name
  end

end
