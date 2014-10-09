#!/usr/bin/env ruby
require 'json'
require 'yaml'
require 'optparse'
require 'date'
require 'nokogiri'
require 'open-uri'
require 'csv'
require 'fileutils'
require_relative 'app'

class Scraping
  attr_accessor :extracted, :appTitle
  @@usage = "Usage: #{$PROGRAM_NAME} csv_file"
  # BASE_URL = 'https://play.google.com'
  # APPS_PATH = '/store/apps'
  # QUERY_STRING = '/details?id='

  def initialize(extracted = false, appTitle = Array.new())
    @extracted = extracted
    @appTitle = appTitle
  end

  private

  def download_drawer(keyword, aapt_dir, output_dir)
    android_drawer_url = "http://androiddrawer.com/search-results/?q=" + keyword
    puts "Downloading #{android_drawer_url}"

    system("phantomjs load_ajax.js '#{android_drawer_url}' search.html")
    browse_query(keyword, aapt_dir, output_dir)
  end

  def browse_query(keyword, aapt_dir, output_dir)
    results = Nokogiri::HTML(open("search.html"))
    linkArray = results.css('a.gs-title')
    linkArray.each do |element|
      if element['href'] != nil
        puts "===== Fetching #{element['href']} ====="
        searchApp =  Nokogiri::HTML(open(element['href']))
        url = element['href']
        title = searchApp.css('h1.entry-title').text.strip.gsub(/\./,"").gsub(/\d+$/,"").gsub(/\s+/,"").gsub(/&/,"").gsub(/[\(\)\:?\/\\%\*|"'\.<>]/,"")
        if appTitle.include?(title) == false
          extract_gen_features(url, title, output_dir)
          if File.directory?("#{output_dir}/#{title}/general")
            package_name, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section = extract_latest_version_features(searchApp, title, aapt_dir, output_dir)
            older_versions = searchApp.css('div.old-version-content-wrap')
            older_versions.each do |version|
              if extracted == false
                package_name, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section = extract_older_version_features(version, package_name, title, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section, aapt_dir, output_dir)
              else
                extract_older_version_features(version, package_name, title, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section, aapt_dir, output_dir)
              end
            end
            @appTitle.push(title)
            @extracted = false
          else
            puts "!!!#{output_dir}/#{title} directory does not exist!!!"
          end
        end
      end
    end
  end

  def extract_gen_features(url, title, output_dir)
    begin
      page = Nokogiri::HTML(open(url))
      title = title.gsub(/\s+/, "")
      app = App.new(title)
      app.title = page.css('h1.entry-title').text.strip
      app.creator = page.css('a.devlink').text.strip
      app.description = page.css('div.app-description-wrap')[0].text.strip
      app.domain = page.css('div#crumbs a')[1].text.strip
      app.category = page.css('div#crumbs a')[2].text.strip
      rootdirectory = "#{output_dir}/#{title}/general"
      FileUtils::mkdir_p "#{rootdirectory}"
      filename = title.to_s + "-general"
      jsondirectory = filename + ".json"
      htmldirectory = filename + ".html"
      system("wget '#{url}' -O #{rootdirectory}/#{htmldirectory}")
      File.open("#{rootdirectory}/#{jsondirectory}", 'wb')  do |f|
        f.write(app.to_json)
      end
    rescue => e
      puts e.message
      puts e.backtrace
      puts "LOCATION: #{url}"
    end
  end

  def extract_latest_version_features(page, title, aapt_dir, output_dir)
    title = title.gsub(/\s+/, "")
    version = Version.new(title)
    version.size = page.css('div.changelog-wrap div.download-wrap a div.download-size').text.strip
    version.update_date = page.css('div.changelog-wrap p.latest-updated-date').text.strip.gsub(/^\S+\s/,"")
    version.version = /\d+(\.\d+)+/.match(page.css('div.app-contents-wrap h3.section-title')[0].text.strip)
    version.what_is_new = page.css('div.changelog-wrap ul').text.strip
    version.download_link = page.css('div.download-wrap a')[0]['href']
    rootdirectory = "#{output_dir}/#{title}/versions/#{version.version}"
    filename = title.to_s + '-' + version.version.to_s
    appname = filename + '.apk'
    app_directory = "#{rootdirectory}/#{appname}"
    jsondirectory = filename + '.json'
    system("mkdir -p #{rootdirectory}")
    system("wget '#{version.download_link}' -O #{app_directory}")
    File.open("#{rootdirectory}/#{jsondirectory}", 'w') do |f|
      f.write(version.to_json)
    end
    package_name, version_name = search_aapt(app_directory, aapt_dir)
    if package_name.nil?
      FileUtils.rm_rf "#{output_dir}/#{title}/versions/#{version.version}"
    else
      if !version_name.nil? && version.version.to_s != version_name.to_s
        FileUtils.mv "#{output_dir}/#{title}/versions/#{version.version}", "#{output_dir}/#{title}/versions/#{version_name}"
      end
      first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section = file_rename(package_name, title, version.version, version_name, aapt_dir, output_dir)
      return package_name, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section
    end
  end

  def file_rename(package_name, title, old_version, version, aapt_dir, output_dir)
    newversionFilename = package_name.to_s + "-" + version.to_s
    newgenFilename = package_name.to_s + "-general"
    newAPK = newversionFilename + '.apk'
    newgenJSON = newgenFilename + '.json'
    newgenHTML = newgenFilename + '.html'
    newversionJSON = newversionFilename + '.json'

    oldgenFilename = title.to_s + "-general"
    oldgenJSON = oldgenFilename + '.json'
    oldgenHTML = oldgenFilename + '.html'
    oldverFilename = title.to_s + '-' + old_version.to_s
    oldverAPK = oldverFilename + '.apk'
    oldverJSON = oldverFilename + '.json'

    if package_name =~ /(^[^\.])([^\.]+)\.([^\.])([^\.]+)\.([^\.]+)/ #blah.blah.blah.blah...
      package_parsing = /(^[^\.])([^\.]+)\.([^\.])([^\.]+)(\.([^\.]+))+/.match(package_name)
      first_package_letter = package_parsing[1]
      first_package_section = package_parsing[1] + package_parsing[2]
      second_package_letter = package_parsing[3]
      second_package_section = package_parsing[3] + package_parsing[4]
      last_package_section = package_parsing[-1]
      rootdirectory = "#{output_dir}/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{last_package_section}"
    else #blah.blah
      package_parsing = /(^[^\.])([^\.]+)\.([^\.])([^\.]+)/.match(package_name)
      first_package_letter = package_parsing[1]
      first_package_section = package_parsing[1] + package_parsing[2]
      second_package_letter = package_parsing[3]
      second_package_section = package_parsing[3] + package_parsing[4]
      rootdirectory = "#{output_dir}/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}"
      last_package_section = ""
    end

    if Dir.exists?("#{rootdirectory}/multiple_versions") && @extracted == false
      puts "!!!!!!File already exists! Deleting #{output_dir}/#{title}"
      FileUtils.rm_rf "#{output_dir}/#{title}"
    else
      FileUtils::mkdir_p "#{rootdirectory}"
      FileUtils.mv("#{output_dir}/#{title.to_s}/general", "#{rootdirectory}")
      FileUtils.mv("#{output_dir}/#{title.to_s}/versions", "#{rootdirectory}/multiple_versions")
      FileUtils.rm_rf "#{output_dir}/#{title.to_s}"

      #Renames version files with apk names
      FileUtils.mv("#{rootdirectory}/multiple_versions/#{version}/#{oldverAPK}", "#{rootdirectory}/multiple_versions/#{version}/#{newAPK}")
      FileUtils.mv("#{rootdirectory}/multiple_versions/#{version}/#{oldverJSON}", "#{rootdirectory}/multiple_versions/#{version}/#{newversionJSON}")
      #Renames general files with apk names
      FileUtils.mv("#{rootdirectory}/general/#{oldgenJSON}", "#{rootdirectory}/general/#{newgenJSON}")
      FileUtils.mv("#{rootdirectory}/general/#{oldgenHTML}", "#{rootdirectory}/general/#{newgenHTML}")
      @extracted = true
    end
    return first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section
  end

  def extract_older_version_features(section, apkname, title, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section, aapt_dir, output_dir)
    title = title.gsub(/\s+/, "")
    versionNum = /\d+(\.\d+)+/.match(section.css('div.download-text').text.strip)
    version = Version.new(versionNum)
    version.version = versionNum
    version.size = section.css('div.download-wrap a div.download-size').text.strip
    if section.css('p.latest-updated-date').text.strip.gsub(/^Added on /,"") != "Added on"
      version.update_date = section.css('p.latest-updated-date').text.strip.gsub(/^Added on /,"")
    else
      version.update_date = "None specified"
    end
    version.what_is_new = section.css('ul').text.strip
    version.download_link = section.css('div.download-wrap a')[0]['href']

    if extracted == false
      rootdirectory = "#{output_dir}/#{title}/versions/#{version.version}"
      filename = title.to_s + '-' + version.version.to_s
      appname = filename + '.apk'
      jsondirectory = filename + '.json'
      app_directory = "#{rootdirectory}/#{appname}"
      system("mkdir -p #{rootdirectory}")
      system("wget '#{version.download_link}' -O #{app_directory}")
      package_name, version_name = search_aapt(app_directory, aapt_dir)
      File.open("#{rootdirectory}/#{jsondirectory}", 'wb') do |f|
        f.write(version.to_json)
      end
      package_name, version_name = search_aapt(app_directory, aapt_dir)
      if package_name.nil?
        FileUtils.rm_rf "#{output_dir}/#{title}/versions/#{version.version}"
      else
        if !version_name.nil? && version.version.to_s != version_name.to_s
          FileUtils.mv("#{output_dir}/#{title}/versions/#{version.version}", "#{output_dir}/#{title}/versions/#{version_name}")
        end
        first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section = file_rename(package_name, title, version.version, version_name, aapt_dir, output_dir)
        return package_name, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section
      end
    else
      filename = apkname.to_s + '-' + version.version.to_s
      if last_package_section.nil?
        rootdirectory = "#{output_dir}/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/multiple_versions"
      else
        rootdirectory = "#{output_dir}/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{last_package_section}/multiple_versions"
      end
      appname = filename + '.apk'
      jsondirectory = filename + '.json'

      FileUtils::mkdir_p "#{rootdirectory}/#{version.version}" unless Dir.exists?("#{rootdirectory}/#{version.version}")
      app_directory = "#{rootdirectory}/#{version.version}/#{appname}"
      system("wget '#{version.download_link}' -O #{app_directory}")
      File.open("#{rootdirectory}/#{version.version}/#{jsondirectory}", 'w') do |f|
        f.write(version.to_json)
      end
      package_name, version_name = search_aapt(app_directory, aapt_dir)
      if package_name.nil?
        FileUtils.rm_rf "#{rootdirectory}/#{version.version}"
      else
        if !version_name.nil? && version.version.to_s != version_name.to_s
          FileUtils.mv("#{rootdirectory}/#{version.version}", "#{rootdirectory}/#{version_name}")
        end
      end
    end
  end

  def search_aapt(directory_path, aapt_dir)
    output = `#{aapt_dir} dump badging #{directory_path} | grep package`
    if output == ""
      return
    else
    pattern = /package\: name='(?<PackageName>\S+)' versionCode='\d+' versionName='(?<VersionName>\S+)'/
    parts = output.match(pattern)
    return parts['PackageName'], parts['VersionName']
    end
  end

  def start_main(packagesArray, aapt_dir, output_dir)
    for keyword in packagesArray
      puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#{keyword}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
      download_drawer(keyword, aapt_dir, output_dir)
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
    output_dir = argv[2]
    aapt_dir = argv[1]
    packagesArray = Array.new()
    CSV.parse(csv_text) do |row|
      row.each do |x|
        packagesArray.push(x.strip.gsub(/^\s+/,""))
      end
    end
    start_main(packagesArray, aapt_dir, output_dir)
  end
end

if __FILE__ ==$PROGRAM_NAME
  scraping = Scraping.new
  scraping.start_command_line(ARGV)
end
