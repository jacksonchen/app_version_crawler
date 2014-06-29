#!/usr/bin/env ruby
require 'json'
require 'yaml'
require 'optparse'
require 'date'
require 'nokogiri'
require 'open-uri'
require 'net/http'
require_relative 'app'
require_relative 'version'

class Scraping
  @@usage = "Usage: #{$PROGRAM_NAME} apk_name"
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

  def browse_drawer(app)
  	android_drawer_url = "http://androiddrawer.com/search-results/?q=" + app.title
  	puts "Fetching #{android_drawer_url}"

    #Add code to load AJAX here

    results = Nokogiri::HTML(open(android_drawer_url))
    link = results.css('a.gs-title')
    puts results
  end

  def browse_query(app)
    results = Nokogiri::HTML(open("search.html"))
    linkArray = results.css('a.gs-title')
    linkArray.each do |element|
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
    appname = app.name.to_s + '-' + version.version.to_s + '.apk'
    puts version.download_link
    #system("wget #{version.download_link} -O apps/#{appname}")
  end

  def start_main(apk_name)
    page = download_file(apk_name)
    app = extract_features(apk_name, page)
    #browse_drawer(app)
    browse_query(app)
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
      puts "Error: apk name is not specified."
      abort(@@usage)
    end
    start_main(argv[0])
  end
end

if __FILE__ ==$PROGRAM_NAME
  scraping = Scraping.new
  scraping.start_command_line(ARGV)
end