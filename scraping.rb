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
        title = searchApp.css('h1.entry-title').text.strip.gsub(/\./,"").gsub(/\d+$/,"").gsub(/\s+$/,"").gsub(/&/,"")
        if appTitle.include?(title) == false
          extract_gen_features(url, title)
          package_name, version_name, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section = extract_latest_version_features(searchApp, title)
          older_versions = searchApp.css('div.old-version-content-wrap')
          older_versions.each do |version|
             if package_name.nil?
              package_name, version_name, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section = extract_older_version_features(version, package_name, title, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section)
             end
             extract_older_version_features(version, package_name, title, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section)
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
    FileUtils::mkdir_p "#{rootdirectory}"
    filename = title.to_s + "-general"
    jsondirectory = filename + ".json"
    htmldirectory = filename + ".html"
    system("wget '#{url}' -O #{rootdirectory}/#{htmldirectory}")
    File.open("#{rootdirectory}/#{jsondirectory}", 'wb')  do |f|
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
    app_directory = "#{rootdirectory}/#{appname}"
    jsondirectory = filename + '.json'
    system("mkdir -p #{rootdirectory}")
    system("wget '#{version.download_link}' -O #{app_directory}")
    File.open("#{rootdirectory}/#{jsondirectory}", 'w') do |f|
      f.write(version.to_json)
    end
    package_name, version_name = search_aapt(app_directory)
    if !package_name.nil?

      newversionFilename = package_name.to_s + "-" + version_name.to_s
      newgenFilename = package_name.to_s + "-general"
      newAPK = newversionFilename + '.apk'
      newgenJSON = newgenFilename + '.json'
      newgenHTML = newgenFilename + '.html'
      newversionJSON = newversionFilename + '.json'

      oldgenFilename = title.to_s + "-general"
      oldgenJSON = oldgenFilename + '.json'
      oldgenHTML = oldgenFilename + '.html'

      if package_name =~ /(^[^\.])([^\.]+)\.([^\.])([^\.]+)\.([^\.]+)/
        package_parsing = /(^[^\.])([^\.]+)\.([^\.])([^\.]+)(\.([^\.]+))+/.match(package_name)
        first_package_letter = package_parsing[1]
        first_package_section = package_parsing[1] + package_parsing[2]
        second_package_letter = package_parsing[3]
        second_package_section = package_parsing[3] + package_parsing[4]
        last_package_section = package_parsing[-1]
        rootdirectory = "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{last_package_section}"
      else
        package_parsing = /(^[^\.])([^\.]+)\.([^\.])([^\.]+)/.match(package_name)
        first_package_letter = package_parsing[1]
        first_package_section = package_parsing[1] + package_parsing[2]
        second_package_letter = package_parsing[3]
        second_package_section = package_parsing[3] + package_parsing[4]
        rootdirectory = "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}"
        last_package_section = ""
      end

      FileUtils::mkdir_p "#{rootdirectory}/multiple_versions" unless Dir.exists?("#{rootdirectory}/multiple_versions")
      FileUtils.mv("apps/#{title.to_s}/general", "#{rootdirectory}")
      FileUtils.mv("apps/#{title.to_s}/versions/#{version.version}", "#{rootdirectory}/multiple_versions")
      FileUtils.rm_rf "apps/#{title.to_s}"

      if version.version != version_name
        File.rename("#{rootdirectory}/multiple_versions/#{version.version}", "#{rootdirectory}/multiple_versions/#{version_name}")
      end

      #Renames version files with apk names
      FileUtils.mv("#{rootdirectory}/multiple_versions/#{version_name}/#{appname}", "#{rootdirectory}/multiple_versions/#{version_name}/#{newAPK}")
      FileUtils.mv("#{rootdirectory}/multiple_versions/#{version_name}/#{jsondirectory}", "#{rootdirectory}/multiple_versions/#{version_name}/#{newversionJSON}")
      #Renames general files with apk names
      FileUtils.mv("#{rootdirectory}/general/#{oldgenJSON}", "#{rootdirectory}/general/#{newgenJSON}")
      FileUtils.mv("#{rootdirectory}/general/#{oldgenHTML}", "#{rootdirectory}/general/#{newgenHTML}")

      return package_name, version_name, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section
    else
      return
    end
  end

  def extract_older_version_features(section, apkname, title, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section)
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
    if first_package_letter.nil?
      rootdirectory = "apps/#{title}/versions/#{version.version}"
      filename = title.to_s + '-' + version.version.to_s
      appname = filename + '.apk'
      jsondirectory = filename + '.json'
      app_directory = "#{rootdirectory}/#{appname}"
    system("mkdir -p #{rootdirectory}")
      system("wget '#{version.download_link}' -O #{app_directory}")
      package_name, version_name = search_aapt(app_directory)
      File.open("#{rootdirectory}/#{jsondirectory}", 'wb') do |f|
        f.write(version.to_json)
      end
      package_name, version_name = search_aapt(app_directory)
      if !package_name.nil?
        newversionFilename = package_name.to_s + "-" + version_name.to_s
        newgenFilename = package_name.to_s + "-general"
        newAPK = newversionFilename + '.apk'
        newgenJSON = newgenFilename + '.json'
        newgenHTML = newgenFilename + '.html'
        newversionJSON = newversionFilename + '.json'

        oldgenFilename = title.to_s + "-general"
        oldgenJSON = oldgenFilename + '.json'
        oldgenHTML = oldgenFilename + '.html'

        if package_name =~ /(^[^\.])([^\.]+)\.([^\.])([^\.]+)\.([^\.]+)/
          package_parsing = /(^[^\.])([^\.]+)\.([^\.])([^\.]+)(\.([^\.]+))+/.match(package_name)
          first_package_letter = package_parsing[1]
          first_package_section = package_parsing[1] + package_parsing[2]
          second_package_letter = package_parsing[3]
          second_package_section = package_parsing[3] + package_parsing[4]
          last_package_section = package_parsing[-1]
          rootdirectory = "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{last_package_section}"
        else
          package_parsing = /(^[^\.])([^\.]+)\.([^\.])([^\.]+)/.match(package_name)
          first_package_letter = package_parsing[1]
          first_package_section = package_parsing[1] + package_parsing[2]
          second_package_letter = package_parsing[3]
          second_package_section = package_parsing[3] + package_parsing[4]
          rootdirectory = "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}"
          last_package_section = ""
        end

        FileUtils::mkdir_p "#{rootdirectory}/multiple_versions" unless Dir.exists?("#{rootdirectory}/multiple_versions")
        FileUtils.mv("apps/#{title.to_s}/general", "#{rootdirectory}")
        FileUtils.mv("apps/#{title.to_s}/versions/#{version.version}", "#{rootdirectory}/multiple_versions")
        FileUtils.rm_rf "apps/#{title.to_s}"

        if version.version != version_name
          File.rename("#{rootdirectory}/multiple_versions/#{version.version}", "#{rootdirectory}/multiple_versions/#{version_name}")
        end

        #Renames version files with apk names
        FileUtils.mv("#{rootdirectory}/multiple_versions/#{version_name}/#{appname}", "#{rootdirectory}/multiple_versions/#{version_name}/#{newAPK}")
        FileUtils.mv("#{rootdirectory}/multiple_versions/#{version_name}/#{jsondirectory}", "#{rootdirectory}/multiple_versions/#{version_name}/#{newversionJSON}")
        #Renames general files with apk names
        FileUtils.mv("#{rootdirectory}/general/#{oldgenJSON}", "#{rootdirectory}/general/#{newgenJSON}")
        FileUtils.mv("#{rootdirectory}/general/#{oldgenHTML}", "#{rootdirectory}/general/#{newgenHTML}")

        return package_name, version_name, first_package_letter, first_package_section, second_package_letter, second_package_section, last_package_section
      end
    else
      filename = apkname.to_s + '-' + version.version.to_s
      if last_package_section.empty?
        rootdirectory = "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/multiple_versions"
      else
        rootdirectory = "apps/#{first_package_letter}/#{first_package_section}/#{second_package_letter}/#{second_package_section}/#{last_package_section}/multiple_versions"
      end
      appname = filename + '.apk'
      jsondirectory = filename + '.json'

      FileUtils::mkdir_p "#{rootdirectory}/#{version.version}" unless Dir.exists?("#{rootdirectory}/#{version.version}")
      app_directory = "#{rootdirectory}/#{version.version}/#{appname}"
      system("wget '#{version.download_link}' -O #{app_directory}")
      package_name, version_name = search_aapt(app_directory)
      if !package_name.nil?
        if version.version != version_name
          File.rename("#{rootdirectory}/#{version.version}", "#{rootdirectory}/#{version_name}")
        end

        File.open("#{rootdirectory}/#{version_name}/#{jsondirectory}", 'w') do |f|
          f.write(version.to_json)
        end
      end
    end
  end

  def search_aapt(directory_path)
    output = `../../adt-bundle/sdk/build-tools/android-4.4W/aapt dump badging #{directory_path} | grep package`
    if output == ""
      return
    else
    pattern = /package\: name='(?<PackageName>\S+)' versionCode='\d+' versionName='(?<VersionName>\S+)'/
    parts = output.match(pattern)
    return parts['PackageName'], parts['VersionName']
    end

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
