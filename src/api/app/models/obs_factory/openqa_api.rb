require 'net/http'

# Commodity class to encapsulate calls to the openQA API.
module ObsFactory
  class OpenqaApi

    class OpenqaFailure < APIException
      setup 408
    end

    def initialize(base_url)
      @base_url = base_url.chomp('/') + '/api/v1/'
    end

    # A get that follows redirects - openqa redirects to https
    def _get(uri, counter_redirects)
      req_path = uri.path
      req_path << "?" + uri.query unless uri.query.empty?
      req = Net::HTTP::Get.new(req_path)
      resp = Net::HTTP.start(uri.host, use_ssl: uri.scheme == "https") { |http| http.request(req) }
      # Prevent endless loop in case response is always 301 or 302
      unless counter_redirects >= 5
        if resp.code.to_i == 302 or resp.code.to_i == 301
          counter_redirects =+ 1
          Rails.logger.debug "following to #{resp.header['location']}"
          return _get(URI.parse(resp.header['location']), counter_redirects)
        end
      end
      return resp
    end

    # Performs a GET query on the openQA API
    #
    # @param [String] url     action to call
    # @param [Hash]   params  query parameters
    # @param [Hash]   options  additional options. Right now :base_url to
    #                   overwrite the default one
    # @return [Object]  the response decoded (usually a Hash)
    def get(url, params = {}, options = {})
      # Check if params for GET request are completely to prevent overhead for openQA
      # and timeouts for the dashboard
      params.each do |key, value|
        if value.nil?
          Rails.logger.error "OpenQA API GET failure: Missing parameters for #{key}"
          return Hash.new
        end
      end

      if options[:base_url]
        uri = URI.join(options[:base_url].chomp('/')+'/', url)
      else
        uri = URI.join(@base_url, url)
      end
      uri.query = params.to_query
      resp = _get(uri, 0)
      unless resp.code.to_i == 200
        Rails.logger.error "OpenQA API GET failure: \"#{url}\" with \"#{params.to_query}\""
        return Hash.new
      end
      ActiveSupport::JSON.decode(resp.body)
    end
  end
end
