require 'digest/sha2' # hexdigest
require 'base64'      # decode64, encode64
require 'openssl'
require 'time'        # Time.parse
require 'fileutils'   # mkdir_p
require 'logger'
require 'etch/server'
require 'tempfile'    # diff


class Etch

  def self.xmlparse(xml_str)
    case Etch.xmllib
    when :libxml
      LibXML::XML::Parser.string(xml_str)
    when :nokogiri
      Nokogiri::XML(xml_str) {|xml|
        # Nokogiri is tolerant of malformed documents by default.  Good when
        # parsing HTML, but there's no reason for us to tolerate errors.  We
        # want to ensure that the user's instructions to us are clear.
        xml.options = Nokogiri::XML::ParseOptions::STRICT
      }
    when :rexml
      REXML::Document.new(xml_str)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end

end  # class Etch


class Etch::PredictServer < Etch::Server
  MaxFileSize = 65535  # default max length of text column in MySQL
  
  def initialize(client, debug=false)
    @dlogger = Logger.new(@@etchdebuglog || File.join(Rails.root, 'log', 'etchdebug.log'))
    @dlogger.level = debug ? Logger::DEBUG : Logger::INFO

    @client = client
    @dlogger.debug "PredictServer for #{@client.name}"

    @facts = client.facts.inject({}) {|r,x| r[x[:key]] = x[:value]; r}
    @orig_sums = client.originals.inject({}) {|r,x| r[x[:file]] = x[:sum]; r}
    @configs = client.etch_configs.inject({}) {|r,x| r[x[:file]] = x[:config]; r}

    @fqdn = @facts['fqdn'] or raise "fqdn fact not supplied"

    @configbase = Etch::Server.configbase
    @dlogger.debug "Using #{@configbase} as config base for node #{@fqdn}"
    File.directory?(@configbase) or raise "Config base #{@configbase} doesn't exist"
    
    # Run the external node tagger
    @tag = `#{File.join(@configbase, 'nodetagger')} #{@fqdn}`.chomp
    $?.success? or raise "External node tagger exited with error #{$?.exitstatus}"
    @dlogger.debug "Tag for node #{@fqdn} from external node tagger: '#{@tag}'"

    @tagbase = File.join(@configbase, @tag)
    @dlogger.debug "Using #{@tagbase} as tagged base for node #{@fqdn}"
    File.directory?(@tagbase) or raise "Tagged base #{@tagbase} doesn't exist"

    @origbase = "#{@configbase}/orig"
  end  # def initialize


  def predict(predict_name, exclude_list = [])
    @dlogger.info "\n===== Starting prediction(#{predict_name}) on: #{@fqdn}"

    # Initial Etch.generate to get the list of files
    etch = Etch.new(Rails.logger, @dlogger)
    response = etch.generate(@tagbase, @facts, {})
    
    request = {}
    # Add the files for which we need original sums or contents
    if response[:need_orig]
      request[:files] ||= {}
      response[:need_orig].each_key {|file|
        next if exclude_list.include?(file)
        if (sha1 = @orig_sums[file])  # if not null
          origpath = File.join(@origbase, file+'.ORIG', sha1)
          File.exist?(origpath) or raise "Original file #{origpath} is missing"
          request[:files][file] = {:orig => origpath}
        else
          # Newly added config, probably.
          @dlogger.info "--- Original is required: #{file}"
          @client.predicts.create(:name => predict_name, :file => file,
              :result => 'newconfig'
          )
        end
      }
      response = etch.generate(@tagbase, @facts, request)
    end  # if response[:need_orig]
    
    # Compare configs for files we generated
    response[:configs] or raise "No configs in the response for #{@fqdn}"
    response[:configs].each {|file, new_config_xml|
      next if exclude_list.include?(file)
      !response[:need_orig][file] or raise "Original is needed for #{file} at second pass"
      last_config_str = @configs[file]
      if last_config_str.size >= MaxFileSize
        # If the previous config XML size was bigger than the max length of
        # text column, it was truncated during "INSERT INTO etch_configs" and
        # we don't have the previous config XML to compare with.
        # Just log it and move on.
        # FIXME: we may want to increase the max length of etch_configs.config
        @dlogger.info "--- file too big: #{file}"
        @client.predicts.create(:name => predict_name, :file => file,
            :result => 'toobig'
        )
      elsif last_config_str != new_config_xml.to_s
        @dlogger.info "--- change: #{file}"
        tempfiles = []
        [ Etch.xmlparse(last_config_str), new_config_xml ].each {|xml|
          content_xml = Etch.xmlfindfirst(xml, '/config/file/contents') 
          tempfiles << Tempfile.new('etchdiff', :encoding => 'ascii-8bit')
          begin
            tempfiles.last.write Base64.decode64(Etch.xmltext(content_xml))
          ensure
            tempfiles.last.close
          end
        }
        diffout = `diff #{tempfiles.map{|f| f.path}.join ' '}`
        tempfiles.each {|f| f.unlink }
        @dlogger.info diffout
        predict = @client.predicts.create(:name => predict_name, :file => file,
            :result => 'change'
        )
        diffout.chomp!
        predict.hashed_contents.create(:type => 'diff',
            :sha2 => Digest::SHA2.hexdigest(diffout),
            :content => diffout
        )
        # FIXME: compare file attributes
      else
        # No change for this file. Moving on.
      end
    }

    # FIXME: need to check for deleted files
    @dlogger.info "===== Finished prediction on: #{@fqdn}"
  end  # def predict

end  # class Etch::PredictServer


namespace :etch do
  desc 'Impact prediction'
  task :predict, [:predict_name] => [:environment] {|t, args|
    args.with_defaults(:predict_name => 'default')

    # FIXME: need a nested loop
    Client.all(
        :limit => 1,
        :order => 'updated_at desc',
        :conditions => ['updated_at > ?', 1.hours.ago]).each {|client|
        #:conditions => ['id = ?', 21400]).each {|client|

      puts client.name

      begin
        client.predicts.create(:name => args.predict_name, :file => 'start')
      rescue ActiveRecord::RecordNotUnique => e
        puts "#{client.name} : already processed"
        # Other worker got this one. Try next one.
        next
      end

      exclude_list = %w{
        /etc/cron.d/etch_update
        /etc/etch/ca.pem
        /etc/etch.conf
        /etc/pki/tls/certs/ca-bundle.crt
      }
      response = Etch::PredictServer.new(client, false).predict args.predict_name, exclude_list
    }
  }
    
end  # namespace :etch do
