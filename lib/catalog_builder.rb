require 'open-uri'
require 'json'
require 'nokogiri'

class CatalogBuilder

  LIBRIVOX_API_URL = "https://librivox.org/api/feed/audiobooks/"
  LIBRIVOX_API_PARMS = "?fields={id,url_librivox,language}&format=json"
  DEFAULT_CATALOG_SIZE = 100
  LIMIT_PER_CALL = 50
  LOCAL_API_RESPONSE_URI_PREFIX = "./fixtures/api_responses/"
  @@special_processing_parm = :none

  def self.build(catalog_size=DEFAULT_CATALOG_SIZE, special_processing=:default, optional_parms="")
    @@special_processing = special_processing
    offset = 0
    records_remaining_to_fetch = catalog_size
    build_timer = Timer.new
    api_timer = Timer.new

    puts "****** BUILDING CATALOG OF AUDIOBOOKS! ****** #{self.current_time}"
    puts "*** Starting API calls and Audiobook initialization"
    while records_remaining_to_fetch > 0
      call_limit = (records_remaining_to_fetch > LIMIT_PER_CALL) ?
                            LIMIT_PER_CALL : records_remaining_to_fetch
      records_remaining_to_fetch -= call_limit

      # puts "** Called API for #{call_limit.to_s} records at offset #{offset.to_s}: " + current_time

      begin
        api_parms = LIBRIVOX_API_PARMS +
            "&offset=" + offset.to_s + "&limit=" + call_limit.to_s + optional_parms
        if @@special_processing != :local_uri_calls &&
              @@special_processing != :local_api_calls
          open(get_local_uri(api_parms), "wb") { |file|
            open(LIBRIVOX_API_URL + api_parms, :read_timeout=>nil) { |uri|
               file.write(uri.read)
            }
          }
        end

        api_result = open(get_local_uri(api_parms), :read_timeout=>nil)

      rescue OpenURI::HTTPError => ex
        if ex.to_s.start_with?("404")
          puts "** HTTP 404 response from Librivox API; apparent end of catalog has been reached! **"
        else
          puts "** Error returned by OpenURI during call to Librivox API. Error message is as follows:"
        end
        puts ex.to_s
        puts "====="
        break
      end
      offset += call_limit
      # puts "** Call to API completed: " + current_time
      json_string = api_result.read
      if (@@special_processing == :local_api_calls ||
              @@special_processing == :local_uri_calls) && json_string.empty?
        puts "***    Apparent end of catalog has been reached while using :local_*_calls special_processing option! **"
        break
      end
      returned_hash = JSON.parse(json_string,{symbolize_names: true})
      hash_array = returned_hash.values[0]
      Audiobook.mass_initialize(hash_array)
      # puts "** Initialization of Audiobook set completed: " + current_time
      # puts "====="
    end
    puts "***    API calls and Audiobooks initialization completed in #{api_timer.how_long?}"

    self.scrape_webpages
    self.build_category_objects
    self.build_solo_group_hashes # must come after Reader category objects instantiated

    puts "****** FULL BUILD OF CATALOG OF #{Audiobook.all.size.to_s} AUDIOBOOKS COMPLETED IN #{build_timer.how_long?} " +
        "****** #{self.current_time}"
  end

  def self.scrape_webpages
    puts "*** Starting scraping of #{Audiobook.all.size.to_s} Librivox webpages"
    scrape_timer = Timer.new
    progress_counter = 0
    # puts "** STARTING scraping of Librivox pages for #{Audiobook.all.size.to_s} audiobooks: " + current_time
    Audiobook.all.each{ |audiobook|
      attributes_hash = ScraperLibrivox.get_audiobook_attributes_hash(
                              audiobook.url_librivox, @@special_processing)
      if !attributes_hash.nil?
        audiobook.add_attributes(attributes_hash)
      end
      # progress_counter += 1
      # if (progress_counter % 100 == 0)
      #   puts "   -- scraping completed for #{progress_counter.to_s} audiobooks -- "  + current_time
      # end
    }
    # puts "** COMPLETED scraping of Librivox pages for #{Audiobook.all.size.to_s} audiobooks: " + current_time
    ##puts "====="
    puts "***    Scraping of #{Audiobook.all.size.to_s} Librivox webpages completed in: #{scrape_timer.how_long?}"

    puts "*** Starting scraping of Gutenberg repository"
    scrape_timer = Timer.new
    # puts "** STARTING scraping of Gutenberg xml docs for #{Audiobook.all_by_gutenberg_id.size.to_s} audiobooks: " + current_time
    ScraperGutenberg.process_gutenberg_genres
    #puts "** COMPLETED scraping of Gutenberg xml docs for #{Audiobook.all_by_gutenberg_id.size.to_s} audiobooks: " + current_time
    #puts "====="
    puts "***    Scraping of Gutenberg repository completed in: #{scrape_timer.how_long?}"
  end

  def self.build_category_objects
    puts "*** Starting initialization of Categories for #{Audiobook.all.size.to_s} audiobooks"
    category_timer = Timer.new
    # puts "** STARTING building of Category objects for #{Audiobook.all.size.to_s} audiobooks: " + current_time
    progress_counter = 0
    Audiobook.all.each{ |audiobook|
      next if audiobook.title.nil?
      audiobook.build_category_objects
      # progress_counter += 1
      # if (progress_counter % 100 == 0)
      #   puts "   -- build of categories completed for #{progress_counter.to_s} audiobooks -- " + current_time
      # end
    }
    # puts "** COMPLETED building of Category objects for #{Audiobook.all.size.to_s} audiobooks: " + current_time
    # puts "====="
    puts "***    Initialization of Categories completed in: #{category_timer.how_long?}"
  end

  def self.build_solo_group_hashes
    puts "*** Starting Solo/Group categorization for #{Audiobook.all.size.to_s} audiobooks"
    solo_group_timer = Timer.new
    # puts "** STARTING building of Solo and Group hashes for #{Audiobook.all.size.to_s} audiobooks: " + current_time
    Audiobook.all.each{ |audiobook|
      audiobook.build_solo_group_hashes
    }
    # puts "** COMPLETED building of Solo and Group hashes for #{Audiobook.all.size.to_s} audiobooks: " + current_time
    # puts "====="
    puts "***    Solo/Group categorization completed in: #{solo_group_timer.how_long?}"
  end

  def self.current_time
    current_time = Time.now.to_s
    current_time = current_time.slice(0,current_time.length - 6)
    return current_time
  end

  def self.get_local_uri(api_parms)
    return LOCAL_API_RESPONSE_URI_PREFIX + api_parms
  end

end

class Timer

  def initialize
    @start_time = Time.now.to_f
  end

  def how_long?
    total_seconds_float = Time.now.to_f - @start_time
    total_seconds = total_seconds_float.to_i
    hundredths_of_second = (((total_seconds_float - total_seconds).round(2)) * 100).to_i
    less_than = ""
    if hundredths_of_second == 0 && total_seconds == 0
      hundredths_of_second = 1 if hundredths_of_second == 0 && total_seconds == 0
      less_than = "< "
    end

    return less_than + "#{(total_seconds / 60).to_s}:#{"%02d"%(total_seconds % 60).to_s}" +
                      ".#{"%02d"%(hundredths_of_second).to_s}"
  end

end
