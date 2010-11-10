require "rubygems"
require 'active_resource'

module StudioApi
  module StudioResource
    def studio_connection
      @studio_connection
    end

    def studio_connection= connection
      self.site = connection.uri.to_s
      #there is general problem, that when specified prefix in model, it doesn't contain uri.path
      # as it is not know and uri is set during runtime, so we must add here manually adapt prefix
      # otherwise site.path is ommitted in models which has own prefix in API
      unless @original_prefix
        if self.prefix_source == join_relative_url(connection.uri.path,'/')
          @original_prefix = "/"
        else
          @original_prefix = self.prefix_source
        end
      end
      self.prefix = join_relative_url connection.uri.path, @original_prefix
      self.user = connection.user
      self.password = connection.password
      self.timeout = connection.timeout
      self.proxy = connection.proxy.to_s if connection.proxy
#FIXME allow pass variable options
      self.ssl_options = connection.ssl
      @studio_connection = connection
    end

    # We need to overwrite the paths methods because susestudio doesn't use the
    # standard .xml filename extension which is expected by ActiveResource.
    def element_path(id, prefix_options = {}, query_options = nil)
      prefix_options, query_options = split_options(prefix_options) if query_options.nil?
      "#{prefix(prefix_options)}#{collection_name}/#{id}#{query_string(query_options)}"
    end

    def collection_path(prefix_options = {}, query_options = nil)
      prefix_options, query_options = split_options(prefix_options) if query_options.nil?
      "#{prefix(prefix_options)}#{collection_name}#{query_string(query_options)}"
    end

    #joins relative url for unix servers
    def join_relative_url(*args)
      args.reduce do |base, append|
        base= base[0..-2] if base.end_with? "/" #remove ending slash in base
        append = append[1..-1] if append.start_with? "/" #remove leading slash in append
        "#{base}/#{append}"
      end
    end
  end
end
