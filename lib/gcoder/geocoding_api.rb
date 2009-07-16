module GCoder
  module GeocodingAPI

    BASE_URI = 'http://maps.google.com/maps/geo'
    BASE_PARAMS = {
      :q => nil,
      :output => 'json',
      :oe => 'utf8',
      :sensor => 'false',
      :key => nil }


    class Request

      def self.get(query, options = {})
        response = new(query, options).get
        response.validate!
        response.to_h
      end

      def initialize(query, options = {})
        unless query
          raise Errors::BlankRequestError, "query cannot be nil"
        end
        unless query.is_a?(String)
          raise Errors::MalformedQueryError, "query must be String, not: #{query.class}"
        end
        @config = Config.merge(options)
        @query = query
        validate_state!
      end

      def params
        BASE_PARAMS.merge(:key => @config[:gmaps_api_key], :q => query)
      end

      def to_params
        params.inject([]) do |array, (key, value)|
          array << "#{uri_escape key}=#{uri_escape value}"
        end.join('&')
      end

      def query
        @config[:append_query] ? "#{@query} #{@config[:append_query]}" : @query
      end

      def uri
        [BASE_URI, '?', to_params].join
      end

      def get
        return @json_response if @json_response
        Timeout.timeout(@config[:gmaps_api_timeout]) do
          Response.new(self)
        end
      rescue Timeout::Error
        raise Errors::RequestTimeoutError, 'The query timed out at ' \
        "#{@config[:gmaps_api_timeout]} second(s)"
      end

      def http_get
        open(uri).read
      end

      protected

      # Snaked from Rack::Utils which 'stole' it from Camping.
      def uri_escape(string)
        string.to_s.gsub(/([^ a-zA-Z0-9_.-]+)/n) do
          '%' + $1.unpack('H2' * $1.size).join('%').upcase
        end.tr(' ', '+')
      end

      def validate_state!
        if '' == query.strip.to_s
          raise Errors::BlankRequestError, 'You must specifiy a query to resolve.'
        end
        unless @config[:gmaps_api_key]
          raise Errors::NoAPIKeyError, 'You must provide a Google Maps API ' \
          'key in your configuration. Go to http://code.google.com/apis/maps/' \
          'signup.html to get one.'
        end
      end

    end


    class Response

      def initialize(request)
        @request = request
        @response = JSON.parse(@request.http_get)
      end

      def status
        @response['Status']['code']
      end

      def validate!
        case status
        when 400
          raise Errors::APIMalformedRequestError, 'The GMaps Geo API has ' \
          'indicated that the request is not formed correctly: ' \
          "(#{@request.uri})\n\n#{@request.inspect}"
        when 602
          raise Errors::APIGeocodingError, 'The GMaps Geo API has indicated ' \
          "that it is not able to geocode the request: (#{@request.uri})" \
          "\n\n#{@request.inspect}"
        end
      end

      def to_h
        { :accuracy => accuracy,
          :country => {
            :name => country_name,
            :code => country_code,
            :administrative_area => administrative_area_name },
          :point => {
            :longitude => longitude,
            :latitude => latitude },
          :box => box }
      end

      def box
        { :north => latlon_box['north'],
          :south => latlon_box['south'],
          :east => latlon_box['east'],
          :west => latlon_box['west'] }
      end

      def accuracy
        address_details['Accuracy']
      end

      def latitude
        coordinates[1]
      end

      def longitude
        coordinates[0]
      end

      def country_name
        country['CountryName']
      end

      def country_code
        country['CountryNameCode']
      end

      def administrative_area_name
        administrative_area['AdministrativeAreaName']
      end

      private

      def coordinates
        point['coordinates'] || []
      end

      def point
        placemark['Point'] || {}
      end

      def country
        address_details['Country'] || {}
      end

      def administrative_area
        country['AdministrativeArea'] || {}
      end

      def address_details
        placemark['AddressDetails'] || {}
      end

      def latlon_box
        extended_data['LatLonBox'] || {}
      end

      def extended_data
        placemark['ExtendedData'] || {}
      end

      def placemark
        @response['Placemark'][0] || {}
      end

    end


  end
end