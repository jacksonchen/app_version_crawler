class App
  attr_accessor :name, :title, :creator, :description, :category,
                :update_date, :size, :what_is_new, :download_link,
                :price, :version_name, :version_code
  
  def to_json
    app_info = {'n' => @name, 't' => @title, 'desc' => @description,
      'url' => @download_link, 'cat' => @category, 'pri' => @price,
      'dtp' => @update_date, 'verc' => @version_code, 'vern' => @version_name,
      'crt' => @creator, 'sztxt' => @size, 'new' => @what_is_new}
      JSON.parse(app_info.to_json)
  end
  
end