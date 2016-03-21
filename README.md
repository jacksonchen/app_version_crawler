#Crawling the Android Drawer
A program using Ruby to scrape data and crawl Android Drawer using [Nokogiri](http://nokogiri.org).

##Usage
```
scraping.rb csv_file aapt_file output_directory
```

Example
```
scraping.rb packages.csv ../../adt-bundle/sdk/build-tools/android-4.4W/aapt apps/
```

You will need to set up a configuration file called `app_version_crawler.conf` where you specify
your command to run aapt (usually it's just `aapt=aapt`).
