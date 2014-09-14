#!/usr/bin/env ruby
require 'json'
require 'yaml'
require 'optparse'
require 'date'
require 'nokogiri'
require 'open-uri'
require 'csv'
require_relative 'app'

class Scraping
  @@usage = "Usage: #{$PROGRAM_NAME} csv_file"
  # BASE_URL = 'https://play.google.com'
  # APPS_PATH = '/store/apps'
  # QUERY_STRING = '/details?id='

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

  def download_drawer(keyword)
    android_drawer_url = "http://androiddrawer.com/search-results/?q=" + keyword
    puts "Downloading #{android_drawer_url}"

    system("phantomjs load_ajax.js '#{android_drawer_url}' search.html")
    browse_query(keyword)
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
    system("mv apps/#{title} apps/#{package_name}")
    if version.version != version_name
      system("mv apps/#{package_name}/versions/#{version.version} apps/#{package_name}/versions/#{version_name}")
    end
    newversionFilename = package_name.to_s + "-" + version_name.to_s
    newgenFilename = package_name.to_s + "-general"
    newAPK = newversionFilename + '.apk'
    newgenJSON = newgenFilename + '.json'
    newgenHTML = newgenFilename + '.html'
    newversionJSON = newversionFilename + '.json'

    oldgenFilename = title.to_s + "-general"
    oldgenJSON = oldgenFilename + '.json'
    oldgenHTML = oldgenFilename + '.html'

    #Renames version files with apk names
    system("mv apps/#{package_name}/versions/#{version_name}/#{appname} apps/#{package_name}/versions/#{version_name}/#{newAPK}")
    system("mv apps/#{package_name}/versions/#{version_name}/#{jsondirectory} apps/#{package_name}/versions/#{version_name}/#{newversionJSON}")
    #Renames general files with apk names
    system("mv apps/#{package_name}/general/#{oldgenJSON} apps/#{package_name}/general/#{newgenJSON}")
    system("mv apps/#{package_name}/general/#{oldgenHTML} apps/#{package_name}/general/#{newgenHTML}")
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

  def firstextract_DrawerFeatures(url, title)
    version = Version.new(title)
    puts "-=-=-=-=-=-=-#{url}-=-=-=-=-=-=-=-=-="
    page = Nokogiri::HTML(open(url))
    version.title = page.css('h1.entry-title').text.strip
    version.creator = page.css('a.devlink').text.strip
    version.update_date = page.css('div#app-details ul li')[7].text.strip
    version.description = page.css('div.tab-contents').children[3..-1].text.strip
    version.size = page.css('div#app-details ul li')[3].text.strip
    version.version = page.css('div#app-details ul li')[5].text.strip
    version.what_is_new = page.css('div.changelog-wrap ul').text.strip
    version.download_link = page.css('div.download-wrap a')[0]['href']
    version.download_link = version.download_link.gsub(/^\S+\//,"https://drive.google.com/")
    puts "-=-=-=-=-=-=-#{version.download_link}-=-=-=-=-=-=-=-=-="
    filename = title.to_s + '-' + version.version.to_s
    rootdirectory = "apps/#{title}/versions/#{version.version}"
    appname = filename + '.apk'
    htmlname = filename + '.html'
    jsondirectory = filename + '.json'
    system("mkdir -p #{rootdirectory}")
    system("wget '#{version.download_link}' -O #{rootdirectory}/#{appname}")
    system("wget '#{url}' -O #{rootdirectory}/#{htmlname}")
    File.open("#{rootdirectory}/#{jsondirectory}", 'w') do |f|
      f.write(version.to_json)
    end
    package_name, version_name = search_aapt(title, version.version, appname, htmlname, jsondirectory)
    system("mv apps/#{title} apps/#{package_name}")
    if version.version != version_name
      system("mv apps/#{package_name}/versions/#{version.version} apps/#{package_name}/versions/#{version_name}")
    end
    newFilename = package_name.to_s + "-" + version_name.to_s
    newAPK = newFilename + '.apk'
    newHTML = newFilename + '.html'
    newJSON = newFilename + '.json'
    system("mv apps/#{package_name}/versions/#{version_name}/#{appname} apps/#{package_name}/versions/#{version_name}/#{newAPK}")
    system("mv apps/#{package_name}/versions/#{version_name}/#{htmlname} apps/#{package_name}/versions/#{version_name}/#{newHTML}")
    system("mv apps/#{package_name}/versions/#{version_name}/#{jsondirectory} apps/#{package_name}/versions/#{version_name}/#{newJSON}")
    return package_name, version_name
  end

  def extract_DrawerFeatures(url, title, packageName)
    version = Version.new(title)
    page = Nokogiri::HTML(open(url))
    version.title = page.css('h1.entry-title').text.strip
    version.creator = page.css('a.devlink').text.strip
    version.update_date = page.css('div#app-details ul li')[7].text.strip
    version.description = page.css('div.tab-contents').children[3..-1].text.strip
    version.size = page.css('div#app-details ul li')[3].text.strip
    version.version = page.css('div#app-details ul li')[5].text.strip
    version.what_is_new = page.css('div.changelog-wrap ul').text.strip
    version.download_link = page.css('div.download-wrap a')[0]['href']
    version.download_link = version.download_link.gsub(/^\S+\//,"https://drive.google.com/")
    filename = title.to_s + '-' + version.version.to_s
    rootdirectory = "apps/#{packageName}/versions/#{version.version}"
    appname = filename + '.apk'
    htmlname = filename + '.html'
    jsondirectory = filename + '.json'
    system("mkdir -p #{rootdirectory}")
    system("wget '#{version.download_link}' -O #{rootdirectory}/#{appname}")
    system("wget '#{url}' -O #{rootdirectory}/#{htmlname}")
    File.open("#{rootdirectory}/#{jsondirectory}", 'w') do |f|
      f.write(version.to_json)
    end
    package_name, version_name = search_aapt(packageName, version.version, appname, htmlname, jsondirectory)
    if version.version != version_name
      system("mv apps/#{packageName}/versions/#{version.version} apps/#{packageName}/versions/#{version_name}")
    end
    newFilename = package_name.to_s + "-" + version_name.to_s
    newAPK = newFilename + '.apk'
    newHTML = newFilename + '.html'
    newJSON = newFilename + '.json'
    system("mv apps/#{packageName}/versions/#{version_name}/#{appname} apps/#{packageName}/versions/#{version_name}/#{newAPK}")
    system("mv apps/#{packageName}/versions/#{version_name}/#{htmlname} apps/#{packageName}/versions/#{version_name}/#{newHTML}")
    system("mv apps/#{packageName}/versions/#{version_name}/#{jsondirectory} apps/#{packageName}/versions/#{version_name}/#{newJSON}")
  end

  def start_main(packagesArray)
    for keyword in packagesArray
      #page = download_file(keyword)
      #app = extract_features(keyword, page)
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
