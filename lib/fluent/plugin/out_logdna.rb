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
    config_param :ingester_domain, :string, default: 'https://logs.logdna.com'

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
      @ingester = HTTP.persistent @ingester_domain
      @requests = Queue.new
    end

    def shutdown
      super
      @ingester.close if @ingester
    end

    def write(chunk)
      body = chunk_to_body(chunk)
      response = send_request(body)
      raise 'Encountered server error' if response.code >= 400
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
      @ingester.headers('apikey' => @api_key,
                        'content-type' => 'application/json')
               .post(url, json: body)
    end
  end
end
