#
#  Copyright (c) 2010 Novell, Inc.
#  All Rights Reserved.
#
#  This library is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Lesser General Public License as
#  published by the Free Software Foundation; version 2.1 of the license.
#
#  This library is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
#  GNU Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public License
#  along with this library; if not, contact Novell, Inc.
#
#  To contact Novell about this file by physical or electronic mail,
#  you may find current contact information at www.novell.com

require 'xmlsimple'
require 'uri'
require 'cgi'
require 'net/http'
require 'net/https'
require 'studio_api/studio_request_exception'

module StudioApi
  class GenericRequest
    def initialize(connection)
      @connection = connection
      if connection.proxy
        proxy = connection.proxy
        @http = Net::HTTP.new(connection.uri.host, connection.uri.port,
            proxy.host, proxy.port, proxy.user, proxy.password)
      else
        @http = Net::HTTP.new(connection.uri.host, connection.uri.port)
      end
      @http.read_timeout = connection.timeout
      if connection.uri.scheme == "https"
        @http.use_ssl = true
        @http.ca_path = connection.ca_path
        @http.verify_mode = connection.verify_mode
      end
    end

    def get(path)
      do_request Net::HTTP::Get.new ::File.join @connection.uri.request_uri,path
    end

    #Even it is not dry I want to avoid meta programming with dynamic code evaluation so code is clear
    def delete(path)
      do_request Net::HTTP::Delete.new ::File.join @connection.uri.request_uri,path
    end

    def post(path,data)
      request = Net::HTTP::Post.new ::File.join @connection.uri.request_uri,path
      set_data(request,data)
      do_request request
    end

    def post(path,data)
      request = Net::HTTP::Put.new ::File.join @connection.uri.request_uri,path
      set_data(request,data)
      do_request request
    end

  private
    def do_request(request)
      @http.start() do
        response = @http.request request
        unless response.kind_of? Net::HTTPSuccess
          raise error_message response
        end
      end
    rescue RuntimeError => e
      raise StudioRequestException.new e.message
    end

    def error_message response
      xml_parsed = XmlSimple.xml_in(response.body, {'KeepRoot' => true})
      raise "Unknown error response from Studio: #{response.body}" unless xml_parsed['error']
      msg = ""
      xml_parsed['error'].each() {|error| msg << error['message']+"\n" }
      return msg
    rescue
      return response.message+"\n"+response.body
    end

    def self.request (uri_path,options)
        # ::File is needed to use "Ruby" file instead this one
      uri      = URI.parse( ::File.join(SLMS::Config.get_value('SUSEStudio', 'restapi'), uri_path ) )
      user     = SLMS::Config.get_value('SUSEStudio', 'user')
      password = SLMS::Config.get_value('SUSEStudio', 'apikey')
      proxy    = SLMS::Proxy::get_proxy_for(uri)

      log.debug("GetRequest #{uri.to_s} " + (proxy.nil? ? "":"via #{proxy.to_s}") )

      begin
        if proxy.nil?
          http = Net::HTTP.new(uri.host, uri.port)
        else
          http = Net::HTTP.new(uri.host, uri.port, proxy.host, proxy.port, proxy.user, proxy.password)
        end
        http.read_timeout = SLMS::Config.get_value('SUSEStudio', 'timeout', 45).to_i
        if uri.scheme == "https"
          http.use_ssl = true
          http.ca_path = SLMS::Config.get_value('SUSEStudio', 'sslcertpath', '/etc/ssl/certs')
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
        http.start() {
          req = Net::HTTP::Get.new(uri.request_uri)
          req.basic_auth user, password
          response = http.request(req)
          unless( response.kind_of? Net::HTTPSuccess )
            begin
              xml_parsed = XmlSimple.xml_in(response.body, {'KeepRoot' => true})
              if not xml_parsed['error'].nil?
                msg = ""
                xml_parsed['error'].each() {|error| msg = error['message'] }
                return ["Error: #{msg}", false]
              end
            rescue
              return ["Error: #{response.message}", false]
            end
          end

          return [response.body, true]
        }
      rescue => e
        return ["Error: #{e.to_s}", false]
      end
    end

    def set_data(request,data)
      boundary = Time.now.to_i.to_s(16)
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      body = ""
      data.each do |key,value|
        esc_key = CGI.escape(key.to_s)
        body << "--#{boundary}\r\n"
        if value.respond_to?(:read) && value.respond_to?(:path)
          # ::File is needed to use "Ruby" file instead this one
          body << "Content-Disposition: form-data; name=\"#{esc_key}\"; filename=\"#{::File.basename(value.path)}\"\r\n"
          body << "Content-Type: #{mime_type(value.path)}\r\n\r\n"
          body << value.read
        else
          body << "Content-Disposition: form-data; name=\"#{esc_key}\"\r\n\r\n#{value}"
        end
        body << "\r\n"
      end
      body << "--#{boundary}--\r\n\r\n"
      request.body = body
      request["Content-Length"] = request.body.size
    end

    def mime_type(file)
      case
        when file =~ /\.jpg\z/ then 'image/jpg'
        when file =~ /\.gif\z/ then 'image/gif'
        when file =~ /\.png\z/ then 'image/png'
        else 'application/octet-stream'
      end
    end
  end
end