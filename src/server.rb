# frozen_string_literal: true

require 'bundler'

Bundler.require

Dotenv.load
Dotenv.require_keys('MOJI_APPCODE', 'CACHE_TTL', 'IOT_MQTT_HOST', 'IOT_MQTT_PORT', 'IOT_MQTT_SSL')

@wxapi = MojiWeather::Api::RestClient.new(app_code: ENV['MOJI_APPCODE'])
@wxapi_simple = nil

unless ENV['MOJI_HAS_BASIC'].nil?
  @wxapi_simple = MojiWeather::Api::RestClient.new(app_code: ENV['MOJI_APPCODE'], cityid_base: 'http://aliv13.data.moji.com/whapi/json/alicityweather')
end

cache = LruRedux::TTL::Cache.new(100, ENV['CACHE_TTL'].to_i)

def extract_device_id(topic)
  devid = %r{iot/weather/(.*)/request}.match(topic)

  if devid.nil?
    nil
  else
    devid[1]
  end
end

def extract_req_type(type)
  wxapi = @wxapi_simple.nil? ? @wxapi : @wxapi_simple

  case type
  when 'condition'
    [MojiWeather::Api::ApiType::CONDITION, wxapi]
  when 'aqi'
    [MojiWeather::Api::ApiType::AQI, wxapi]
  when 'forecast24h'
    [MojiWeather::Api::ApiType::FORECAST_24HRS, @wxapi]
  when 'forecast6d'
    [MojiWeather::Api::ApiType::FORECAST_6DAYS, wxapi]
  when 'forecast15d'
    [MojiWeather::Api::ApiType::FORECAST_15DAYS, @wxapi]
  else
    [nil, nil]
  end
end

client = MQTT::Client.new
begin
  client.host = ENV['IOT_MQTT_HOST']
  client.port = ENV['IOT_MQTT_PORT'].to_i

  unless ENV['IOT_MQTT_SSL'].nil? || ENV['IOT_MQTT_SSL'] == 'false' || ENV['IOT_MQTT_SSL'] == 'no'
    client.ssl = true
    client.cert_file = ENV['IOT_MQTT_SSL_CERT_FILE']
    client.key_file = ENV['IOT_MQTT_SSL_KEY_FILE']
    client.ca_file = ENV['IOT_MQTT_SSL_CA_FILE']
  end

  client.connect

  puts "[#{Time.now}] client [#{client}] connected..."

  client.subscribe('iot/weather/#')

  client.get do |topic, payload|
    # this method also checks if this is from a request topic.
    dev_id = extract_device_id(topic)
    unless dev_id.nil?
      puts "[#{Time.now}][#{dev_id}] <- #{payload.length}B"

      # decode CBOR object, retrieve request.
      dev_req = CBOR.decode(payload)

      wx_cond, wxapi = extract_req_type(dev_req['type'])

      # Not a valid type
      next if wx_cond.nil?

      req_params = if !dev_req['city_id'].nil?
                     { city_id: dev_req['city_id'] }
                   elsif !dev_req['location'].nil?
                     { location: { lat: dev_req['location']['lat'], lon: dev_req['location']['lon'] } }
                   else
                     puts "[#{Time.now}][#{dev_id}] not a valid request"
                     next
                   end

      req_params[:type] = wx_cond

      # Check cache
      api_resp = cache["cache_#{req_params}"]

      # Cache missed..
      if api_resp.nil?
        puts "[#{Time.now}][#{dev_id}] cache missed"
        # Request external service for weather information
        api_resp = wxapi.query(wx_cond, req_params)

        # Update cache entry
        cache["cache_#{req_params}"] = api_resp
      else
        puts "[#{Time.now}][#{dev_id}] cache hit"
      end

      # Encode CBOR object
      resp = api_resp.to_cbor

      # Publish to response topic.
      puts "[#{Time.now}][#{dev_id}] -> #{resp.length}B"

      # Send response
      client.publish("iot/weather/#{dev_id}/response", resp)
    end
  end
rescue SystemExit, Interrupt
  puts "[#{Time.now}] Interrupt caught, client [#{client}] disconnect."
  client.disconnect
rescue StandardError => e
  p e
end
