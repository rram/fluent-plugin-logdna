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
      require 'base64'
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
      line = {
        level: record['level'] || record['severity'] || tag.nil? ? "INFO" : tag.split('.').last,
        timestamp: time,
        line: record.to_json
      }
      # At least one of "file" or "app" is required.
      line[:file] = record['file']
      line[:file] ||= @file if @file
      line.delete(:file) if line[:file].nil?
      line[:app] = record['_app'] || record['app']
      line[:app] ||= @app if @app
      line.delete(:app) if line[:app].nil?

      line[:meta] = record['meta']
      line.delete(:meta) if line[:meta].nil?
      line
    end

    def send_request(body)
      now = Time.now.to_i
      url = "/logs/ingest?hostname=#{@host}&mac=#{@mac}&ip=#{@ip}&now=#{now}"
      log.debug "Sending #{body[:lines].size} lines to #{@ingester_host}#{url}"
      @ingester.headers('apikey' => @api_key,
                        'content-type' => 'application/json')
               .post(url, json: body)
    end
  end
end
