require 'fluent/plugin/output'

module Fluent::Plugin
  class LogDNAOutput < Output
    Fluent::Plugin.register_output('logdna', self)

    config_param :api_key, :string, secret: true
    config_param :hostname, :string
    config_param :mac, :string, default: nil
    config_param :ip, :string, default: nil
    config_param :app, :string, default: nil
    config_param :file, :string, default: nil
    config_param :ingester_host, :string, default: 'https://logs.logdna.com'

    def configure(conf)
      super
      @host = conf['hostname']
    end

    def start
      super
      require 'json'
      require 'http'
      HTTP.default_options = { :keep_alive_timeout => 60 }
      @ingester = HTTP.persistent @ingester_host
      @requests = Queue.new
    end

    def shutdown
      super
      @ingester.close if @ingester
    end

    def write(chunk)
      body = chunk_to_body(chunk)
      response = send_request(body)
      if response.code >= 400
        error = {
          http_code: response.code,
          http_reason: response.reason,
        }
        begin
          body = response.body
          extra_info = JSON.parse body
        rescue
          extra_info = {:message => body.to_s}
        end
        error.merge!(extra_info)
        log.error error
        raise "Encountered server error when sending to LogDNA. Check fluentd logs for more information"
      end
      response.flush
    end

    private

    def chunk_to_body(chunk)
      data = []

      chunk.each do |(time, record)|
        data << gather_line_data(chunk.metadata.tag, time, record)
      end

      { lines: data }
    end

    def gather_line_data(tag, time, record)
      # record is a fluentd record which looks close to what we're going to send to LogDNA.
      # We need to promote a couple of fields (providing some defaults), and then send
      # everything else as-is.
      line = {
        level: record['level'] || record['severity'] || tag.nil? ? "INFO" : tag.split('.').last,
        timestamp: time,
      }

      # The default JSON library will raise an exception if encoding fails.
      # The HTTPrb library will attempt to encode all json content into UTF-8.
      # Therefore we need to clense invalid UTF-8 that may be in your message
      # (say because you're logging raw user input or binary files...). We'll
      # also set encoding_error to true so that you know the message has been
      # lossily altered.
      begin
        record['message'].encode!("UTF-8")
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        record['message'].encode!(
          "UTF-8",
          "BINARY",
          :invalid => :replace,
          :undef => :replace,
        )
        record[:encoding_error] = true
      end
      line[:line] = JSON.dump record

      # At least one of "file" or "app" is required.
      # Use the defaults from the fluentd config if necessary.
      line[:file] = record['file'] || @file
      line[:app] = record['_app'] || record['app'] || @app
      # Fallback to prevent a persistent 400 error from LogDNA
      unless line[:file] or line[:app]
        line[:app] = "<UNKNOWN>"
      end

      # Attach metadata if it exists
      if record['meta']
        line[:meta] = record['meta']
      end

      line.compact
    end

    def send_request(body)
      now = Time.now.to_i
      url = "/logs/ingest?hostname=#{@host}&mac=#{@mac}&ip=#{@ip}&now=#{now}"
      log.debug "Sending #{body[:lines].size} lines to #{@ingester_host}#{url}"
      @ingester.headers('apikey' => @api_key)
               .post(url, json: body)
    end
  end
end
