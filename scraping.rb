#!/usr/bin/env ruby
require 'json'
require 'yaml'
require 'optparse'
require 'date'
require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'csv'
require_relative 'app'

class Scraping
  @@usage = "Usage: #{$PROGRAM_NAME} csv_file_name"
  BASE_URL = 'https://play.google.com'
  APPS_PATH = '/store/apps'
  QUERY_STRING = '/details?id='

  private
  def download_file(apk_name)
    play_store_url = BASE_URL + APPS_PATH + QUERY_STRING + apk_name
    puts "Fetching #{play_store_url}"
    begin
      page = Nokogiri::HTML(open(play_store_url))
    rescue OpenURI::HTTPError
      puts "Error: HTTP error in the given URL: #{play_store_url}."
      exit
    rescue OpenURI::HTTPRedirect
      puts "Error: HTTP redirect error in the given URL: #{play_store_url}."
      exit
    end
  end

  def extract_features(apk_name, page)
    app = App.new(apk_name)
    app.title = page.css('div.info-container div.document-title').text.strip
    title_arr = page.css('div.info-container .document-subtitle')
    app.creator = title_arr[0].text.strip
    puts app.to_json
    return app
  end

  def download_drawer(app)
  	android_drawer_url = "http://androiddrawer.com/search-results/?q=" + app.title
  	puts "Downloading #{android_drawer_url}"

    system("phantomjs load_ajax.js '#{android_drawer_url}' search.html")
    browse_query(app)
  end

  def browse_query(app)
    results = Nokogiri::HTML(open("search.html"))
    linkArray = results.css('a.gs-title')
    linkArray.each do |element|
    system("mkdir apps/#{app.title}")
      if element['href'] != nil
        puts "===== Fetching #{element['href']} ====="
        searchApp =  Nokogiri::HTML(open(element['href']))
        title = searchApp.css('h1.entry-title').text.strip.gsub(/\./,"").gsub(/\d+$/,"").gsub(/\s+$/,"")
        if app.title == title
          puts "Instances of #{app.title} found"
          latestVersion = searchApp.css('ul.latest-version li a')
          puts "===== Fetching #{latestVersion[0]['href']} ====="
          extract_DrawerFeatures(latestVersion[0]['href'], app)
          oldVersion = searchApp.css('ul.oldversions li a')
          oldVersion.each do |version|
            puts "===== Fetching #{version['href']} ====="
            extract_DrawerFeatures(version['href'], app)
          end
          break
        end
      end
    end
  end

  def extract_DrawerFeatures(url, app)
    version = Version.new(app.name)
    page = Nokogiri::HTML(open(url))
    version.title = page.css('h1.entry-title').text.strip
    version.creator = page.css('a.devlink').text.strip
    version.update_date = page.css('div#app-details ul li')[7].text.strip
    version.description = page.css('div.tab-contents').children[3..-1].text.strip
    version.size = page.css('div#app-details ul li')[3].text.strip
    version.version = page.css('div#app-details ul li')[5].text.strip
    version.what_is_new = page.css('div.changelog-wrap ul').text.strip
    version.download_link = page.css('div.download-wrap a')[0]['href']
    filename = app.name.to_s + '-' + version.version.to_s
    appname = filename + '.apk'
    htmlname = filename + '.html'
    jsondirectory = filename + '.json'
    #system("wget '#{version.download_link}' -O /home/user/drawer/apps/#{appname}")
    #system("wget '#{url}' -O /home/user/drawer/apps/#{htmlname}")
    system("wget '#{version.download_link}' -O apps/#{app.title}/#{appname}")
    system("wget '#{url}' -O apps/#{app.title}/#{htmlname}")
    #system("app")
    File.open("apps/#{app.title}/#{jsondirectory}", 'w') do |f|
      f.write(version.to_json)
    end
  end

  def start_main(packagesArray)
    for apk_name in packagesArray
      page = download_file(apk_name)
      app = extract_features(apk_name, page)
      download_drawer(app)
    end
  end

  public
  def start_command_line(argv)
    begin
      opt_parser = OptionParser.new do |opts|
        opts.banner = @@usage
        opts.on('-h','--help', 'Show this help message and exit.') do
          puts opts
          exit
        end
      end
      opt_parser.parse!
    rescue OptionParser::AmbiguousArgument
      puts "Error: illegal command line argument."
      puts opt_parser.help()
      exit
    rescue OptionParser::InvalidOption
      puts "Error: illegal command line option."
      puts opt_parser.help()
      exit
    end
    if(argv[0].nil?)
      puts "Error: csv file name is not specified."
      abort(@@usage)
    end

    csv_text = File.read(argv[0])
    packagesArray = Array.new()
    CSV.parse(csv_text) do |row|
      packagesArray.push(row[0])
    end
    packagesArray.shift
    puts packagesArray

    start_main(packagesArray)
  end
end

if __FILE__ ==$PROGRAM_NAME
  scraping = Scraping.new
  scraping.start_command_line(ARGV)
end
