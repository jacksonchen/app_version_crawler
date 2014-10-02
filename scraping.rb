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
  @@usage = "Usage: #{$PROGRAM_NAME} csv_file"
  # BASE_URL = 'https://play.google.com'
  # APPS_PATH = '/store/apps'
  # QUERY_STRING = '/details?id='

  private

  def download_drawer(keyword)
    android_drawer_url = "http://androiddrawer.com/search-results/?q=" + keyword
    puts "Downloading #{android_drawer_url}"

    system("phantomjs load_ajax.js '#{android_drawer_url}' search.html 1")
    results = Nokogiri::HTML(open("search.html"))
    pages = results.css('div.gsc-cursor')
    pages.each do |pageNum|
      system("phantomjs load_ajax.js '#{android_drawer_url}' search.html #{pageNum}")
      browse_query(keyword)
    end
  end

  def browse_query(keyword)
    results = Nokogiri::HTML(open("search.html"))
    appTitle = Array.new()
    linkArray = results.css('a.gs-title')
    linkArray.each do |element|
      if element['href'] != nil
        puts "===== Fetching #{element['href']} ====="
        searchApp =  Nokogiri::HTML(open(element['href']))
        url = element['href']
        title = searchApp.css('h1.entry-title').text.strip.gsub(/\./,"").gsub(/\d+$/,"").gsub(/\s+$/,"")
        if appTitle.include?(title) == false
          extract_gen_features(url, title)
          package_name, version_name = extract_latest_version_features(searchApp, title)
          break
          older_versions = searchApp.css('div.old-version-content-wrap')
          older_versions.each do |version|
             extract_older_version_features(version, package_name, title)
          end
          appTitle.push(title)
        end
      end
    end
  end

  def extract_gen_features(url, title)
    page = Nokogiri::HTML(open(url))
    title = title.gsub(/\s+/, "")
    app = App.new(title)
    app.title = page.css('h1.entry-title').text.strip
    app.creator = page.css('a.devlink').text.strip
    app.description = page.css('div.app-description-wrap')[0].children.text.strip
    app.domain = page.css('div#crumbs a')[1].text.strip
    app.category = page.css('div#crumbs a')[2].text.strip
    rootdirectory = "apps/#{title}/general"
    system("mkdir -p #{rootdirectory}")
    filename = title.to_s + "-general"
    jsondirectory = filename + ".json"
    htmldirectory = filename + ".html"
    system("wget '#{url}' -O #{rootdirectory}/#{htmldirectory}")
    File.open("#{rootdirectory}/#{jsondirectory}", 'w')  do |f|
      f.write(app.to_json)
    end
  end

  def extract_latest_version_features(page, title)
    title = title.gsub(/\s+/, "")
    version = Version.new(title)
    version.size = page.css('div.changelog-wrap div.download-wrap a div.download-size').text.strip
    version.update_date = page.css('div.changelog-wrap p.latest-updated-date').text.strip.gsub(/^\S+\s/,"")
    version.version = page.css('div.app-contents-wrap h3.section-title')[0].text.strip.gsub(/^\S+\s\S+\s/,"")
    version.what_is_new = page.css('div.recent-change').text.strip
    version.download_link = page.css('div.download-wrap a')[0]['href']
    rootdirectory = "apps/#{title}/versions/#{version.version}"
    filename = title.to_s + '-' + version.version.to_s
    appname = filename + '.apk'
    jsondirectory = filename + '.json'
    system("mkdir -p #{rootdirectory}")
    system("wget '#{version.download_link}' -O #{rootdirectory}/#{appname}")
    File.open("#{rootdirectory}/#{jsondirectory}", 'w') do |f|
      f.write(version.to_json)
    end
    package_name, version_name = search_aapt(title, version.version, appname, jsondirectory)
    puts "~~~~~~~~~~~~~~~#{package_name}~~~~~~~~~~~"
    if package_name =~ /(^[^\.])([^\.]+)\.([^\.])([^\.]+)\.([^\.]+)/
      package_parsing = /(^[^\.])([^\.]+)\.([^\.])([^\.]+)(\.([^\.]+))+/.match(package_name)
      first_package_letter = package_parsing[1]
      first_package_section = package_parsing[1] + package_parsing[2]
      second_package_letter = package_parsing[3]
      second_package_section = package_parsing[3] + package_parsing[4]
      last_package_section = package_parsing[-1]
      FileUtils::mkdir_p "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{last_package_section}/multiple_versions" unless Dir.exists?("apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{last_package_section}/multiple_versions")
      FileUtils.mv("apps/#{title.to_s}/general", "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{last_package_section}")
      File.rename("apps/#{title.to_s}/versions", "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{last_package_section}/multiple_versions")
      FileUtils.rmdir "apps/#{title.to_s}"
    else
      package_parsing = /(^[^\.])([^\.]+)\.([^\.])([^\.]+)/.match(package_name)
      first_package_letter = package_parsing[1]
      first_package_section = package_parsing[1] + package_parsing[2]
      second_package_letter = package_parsing[3]
      second_package_section = package_parsing[3] + package_parsing[4]
      FileUtils::mkdir_p "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/multiple_versions" unless Dir.exists?("apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/multiple_versions")
      FileUtils.mv("apps/#{title.to_s}/general", "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/multiple_versions")
    end
    # if version.version != version_name
    #   FileUtils.mv("apps/#{package_name}/versions/#{version.version} apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{package_name}/multiple_versions")
    # end
    # newversionFilename = package_name.to_s + "-" + version_name.to_s
    # newgenFilename = package_name.to_s + "-general"
    # newAPK = newversionFilename + '.apk'
    # newgenJSON = newgenFilename + '.json'
    # newgenHTML = newgenFilename + '.html'
    # newversionJSON = newversionFilename + '.json'

    # oldgenFilename = title.to_s + "-general"
    # oldgenJSON = oldgenFilename + '.json'
    # oldgenHTML = oldgenFilename + '.html'

    # #Renames version files with apk names
    # FileUtils.mv("apps/#{package_name}/versions/#{version_name}/#{appname}", "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{package_name}/multiple_versions/#{version_name}/#{newAPK}")
    # FileUtils.mv("apps/#{package_name}/versions/#{version_name}/#{jsondirectory}", "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{package_name}/multiple_versions/#{version_name}/#{newversionJSON}")
    # #Renames general files with apk names
    # FileUtils.mv("apps/#{package_name}/general/#{oldgenJSON}", "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{package_name}/multiple_versions/general/#{newgenJSON}")
    # FileUtils.mv("apps/#{package_name}/general/#{oldgenHTML}", "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{package_name}/multiple_versions/general/#{newgenHTML}")
    return package_name, version_name
  end

  def extract_older_version_features(section, apkname, title)
    title = title.gsub(/\s+/, "")
    versionNum = /\d+(.\d+)+$/.match(section.css('div.download-text').text.strip)
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

    filename = apkname.to_s + '-' + version.version.to_s
    rootdirectory = "apps/#{apkname}/versions/#{version.version}"
    appname = filename + '.apk'
    jsondirectory = filename + '.json'
    system("mkdir -p #{rootdirectory}")
    system("wget '#{version.download_link}' -O #{rootdirectory}/#{appname}")
    File.open("#{rootdirectory}/#{jsondirectory}", 'w') do |f|
      f.write(version.to_json)
    end
    package_name, version_name = search_aapt(title, version.version, appname, jsondirectory)
    if version.version != version_name
      system("mv apps/#{apkname}/versions/#{version.version} apps/#{apkname}/versions/#{version_name}")
    end
  end

  def search_aapt(appName, version, apkname, jsondirectory)
    output = `../../adt-bundle/sdk/build-tools/android-4.4W/aapt dump badging apps/#{appName}/versions/#{version}/#{apkname} | grep package`
    if output == ""
      corrupt_name = version.to_s + "corrupt"
      system("mv apps/#{appName}/versions/#{version} apps/#{appName}/versions/#{corrupt_name}")
      return
    end
    pattern = /package\: name='(?<PackageName>\S+)' versionCode='\d+' versionName='(?<VersionName>\S+)'/
    parts = output.match(pattern)
    return parts['PackageName'], parts['VersionName']
  end

  def start_main(packagesArray)
    for keyword in packagesArray
      download_drawer(keyword)
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
      row.each do |x|
        packagesArray.push(x.strip.gsub(/^\s+/,""))
      end
    end
    start_main(packagesArray)
  end
end

if __FILE__ ==$PROGRAM_NAME
  scraping = Scraping.new
  scraping.start_command_line(ARGV)
end
