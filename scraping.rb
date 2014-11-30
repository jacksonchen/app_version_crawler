#!/usr/bin/env ruby
require 'json'
require 'yaml'
require 'optparse'
require 'date'
require 'nokogiri'
require 'open-uri'
require 'csv'
require 'fileutils'
require 'timeout'
require_relative 'app'
require_relative 'log'
require_relative 'aapt_executor'

class Scraping
  @@log = nil
  @@usage = "Usage: #{$PROGRAM_NAME} keywords_file out_dir"
  BASE_URL = 'http://androiddrawer.com'
  SEARCH_PATH = '/search-results'
  QUERY_STRING = '/?q='

  def initialize()
    # Seed URLs to ensure that webpages are fetched only once
    @seeds= Array.new()
  end

  private

  def download_drawer(keyword)
    android_drawer_url = BASE_URL + SEARCH_PATH + QUERY_STRING + keyword
    @@log.info("Downloading #{android_drawer_url}")
    html_doc = IO.popen("phantomjs load_ajax.js '#{android_drawer_url}'")
    html_doc = html_doc.read
  end

  def browse_query(keyword, html_doc, output_dir)
    results = Nokogiri::HTML(html_doc)
    linkArray = results.css('a.gs-title')
    linkArray.each do |element|
      if element['href'] != nil
        @@log.info("===== Fetching #{element['href']} =====")
        begin
          searchApp = ""
          Timeout.timeout(240) do
            searchApp =  Nokogiri::HTML(open(element['href']))
          end
          url = element['href']
          #checks if url exists, if url is not already seeded, and if the page is a normal page (e.g not a help or blog page)
          if !url.nil? and !@seeds.include?(url) and searchApp.at_css('h1.entry-title') and searchApp.at_css('div.app-description-wrap')
            # Extract general features and download HTML page
            app = extract_gen_features(url, output_dir)
            if app.nil?
              continue
            end
            # Extract version specific information
            (app, out_path) = extract_latest_version_features(searchApp, app, output_dir)
            # get older versions
            if out_path.nil?
              (app, out_path) = parse_old_versions(searchApp, app, out_path, output_dir)
            else
              parse_old_versions(searchApp, app, out_path, "")
            end
            # Add URL to seeds
            @seeds << url
          end
        rescue Timeout::Error
          @@log.error("TIMEOUT ERROR: The app page '#{element['href']}' will be skipped since its query is hung")
        end
      end
    end
  end

  def parse_old_versions(page, app, out_path, old_root_dir)
    versions = page.css('div.old-version-list h2.old-version-title')
    links = page.css('div.download-wrap a.download-btn')
    added_dates = page.css('div.old-version-content-wrap p.latest-updated-date')
    all_changes_list = page.css('div.old-version-content-wrap ul')

    new_changes = []
    all_changes_list.each do |change|
      new_changes << change.text.strip
    end
    if out_path.nil?
      apk_tmp_full_path = "#{old_root_dir}tmp.apk"
    else
      apk_tmp_full_path = File.join(out_path, "tmp.apk")
    end
    versions.zip(links, added_dates, new_changes).each do |version, link, added_date, change|
      @@log.info("version: " + version.text.strip)
      app.download_link = link['href']
      app.what_is_new = new_changes.join(',')
      app.update_date = added_date.text.strip.gsub(/^Added on /,"")

      system("wget -q '#{app.download_link}' -O #{apk_tmp_full_path}")
      # Get version name and version code info from aapt tool
      version_info = get_version_info(apk_tmp_full_path)
      package_name = version_info[:package]
      version_code = version_info[:version_code]
      version_name = version_info[:version_name]
      app.name = package_name
      app.version_code = version_code
      app.version_name = version_name

      if !package_name.nil? && !version_name.nil? && !version_code.nil?
        if out_path.nil?
          all_versions_dir = rename_file(old_root_dir, package_name, version_code, apk_tmp_full_path, app)
          return app, all_versions_dir
        else
          version_directory = File.join(out_path, version_code)
          FileUtils.mkdir_p version_directory
          base_name = "#{package_name}-#{version_code}"
          apk_full_path = File.join(version_directory, base_name + ".apk")
          # move the apk file
          system("mv #{apk_tmp_full_path} #{apk_full_path}")

          json_file = base_name + '.json'
          File.open("#{version_directory}/#{json_file}", 'w') do |f|
            f.write(JSON.pretty_generate(app.to_json))
          end
        end
      end
    end
  end


  # Extract general app information and download HTML page.
  def extract_gen_features(url, root_dir)
    begin
      page = Nokogiri::HTML(open(url))
      app = App.new()
      app.title = page.css('h1.entry-title').text.strip
      app.creator = page.css('a.devlink').text.strip
      app.description = page.css('div.app-description-wrap')[0].text.strip
      app.category = page.css('div#crumbs a')[2].text.strip
      app.price = 'Free'
      html_out = "tmp.html"
      # Download HTML page
      system("wget -q '#{url}' -O #{html_out}")
      app
    rescue => e
      @@log.error(e.message)
      @@log.error(e.backtrace)
      @@log.error("LOCATION: #{url}")
    end
  end

  # Extract version specific information and download apk file
  def extract_latest_version_features(page, app, root_dir)
    app.size = page.css('div.changelog-wrap div.download-wrap a div.download-size').text.strip
    app.update_date = page.css('div.changelog-wrap p.latest-updated-date').text.strip.gsub(/^\S+\s/,"")
    app.what_is_new = page.css('div.changelog-wrap ul').text.strip
    app.download_link = page.css('div.download-wrap a')[0]['href']

    apk_tmp_full_path = "#{root_dir}tmp.apk"
    system("wget -q '#{app.download_link}' -O #{apk_tmp_full_path}")

    # Get version name and version code info from aapt tool
    version_info = get_version_info(apk_tmp_full_path)
    package_name = version_info[:package]
    version_code = version_info[:version_code]
    version_name = version_info[:version_name]
    app.name = package_name
    app.version_code = version_code
    app.version_name = version_name

    if !package_name.nil? && !version_name.nil? && !version_code.nil?
      all_versions_dir = rename_file(root_dir, package_name, version_code, apk_tmp_full_path, app)
    end
    return app, all_versions_dir
  end

  def rename_file(root_dir, package_name, version_code, apk_tmp_full_path, app)
    package_parts = package_name.split('.')
    all_versions_dir = File.join(root_dir, package_parts[0][0], package_parts[0], package_parts[1][0], package_parts[1], package_name, 'versions')
    base_name = "#{package_name}-#{version_code}"
    version_directory = File.join(all_versions_dir, version_code)
    FileUtils.mkdir_p version_directory
    apk_full_path = File.join(version_directory, base_name + ".apk")
    # move the apk file
    system("mv #{apk_tmp_full_path} #{apk_full_path}")
    # move the html file
    html_file_path = File.join(all_versions_dir, base_name + ".html")
    system("mv tmp.html #{html_file_path}")
    json_file = base_name + '.json'
    File.open("#{version_directory}/#{json_file}", 'w') do |f|
      f.write(JSON.pretty_generate(app.to_json))
    end
    return all_versions_dir
  end

  # Get version name and version code using aapt from the apk file
  def get_version_info(apk_file)
    version_info = Hash.new
    if(File.exist? apk_file)
      @@log.info("Running aapt on APK file: #{apk_file}")
      aapt_executor = AaptExecutor.new(apk_file)
      version_info = aapt_executor.get_version_info
    else
      @@log.error("APK file does not exist. #{apk_file}")
    end
    version_info
  end

  def start_main(keywords, output_dir)
    beginning_time = Time.now
    for keyword in keywords
      @@log.info("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~Keyword: #{keyword}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
      begin
        html_doc = ""
        Timeout.timeout(240) do
          html_doc = download_drawer(keyword)
        end
        browse_query(keyword, html_doc, output_dir)
      rescue Timeout::Error
        @@log.error("TIMEOUT ERROR: The keyword '#{keyword}' will be skipped since its query is hung")
      end
    end
    end_time = Time.now
    elapsed_seconds = end_time - beginning_time
    puts "Finished after #{Time.at(elapsed_seconds).utc.strftime("%H:%M:%S")}"
  end

  public
  def start_command_line(argv)
    log_file_name = nil
    begin
      opt_parser = OptionParser.new do |opts|
        opts.banner = @@usage
        opts.on('-h','--help', 'Show this help message and exit.') do
          puts opts
          exit
        end
        opts.on('-l','--log <log_file>', 'Write error level logs to the specified file.') do |log_file|
          log_file_name = log_file
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
      puts "Error: keyword file name is not specified."
      abort(@@usage)
    end
    if(argv[1].nil?)
      puts "Error: target directory is not specified."
      abort(@@usage)
    end
    Log.log_file_name = log_file_name
    @@log = Log.instance

    csv_text = File.read(argv[0])
    output_dir = argv[1]
    packagesArray = Array.new()
    CSV.parse(csv_text) do |row|
      row.each do |x|
        packagesArray.push(x.strip.gsub(/^\s+/,""))
      end
    end
    start_main(packagesArray, output_dir)
  end
end

if __FILE__ ==$PROGRAM_NAME
  # Load configurations
  Settings.load('./config/app_version_crawler.conf')
  scraping = Scraping.new
  scraping.start_command_line(ARGV)
end
