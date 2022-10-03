# frozen_string_literal: true

require 'bundler'

Bundler.require

Dotenv.load
Dotenv.require_keys('MOJI_APPCODE', 'IOT_MQTT_HOST', 'IOT_MQTT_PORT', 'IOT_MQTT_SSL')

CITY_ID = 3

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

  client.subscribe('iot/weather/testclient/response')

  client.publish('iot/weather/testclient/request', { type: 'condition', city_id: CITY_ID }.to_cbor)
  client.publish('iot/weather/testclient/request', { type: 'aqi', city_id: CITY_ID }.to_cbor)
  client.publish('iot/weather/testclient/request', { type: 'forecast24h', city_id: CITY_ID }.to_cbor)
  client.publish('iot/weather/testclient/request', { type: 'forecast6d', city_id: CITY_ID }.to_cbor)
  client.publish('iot/weather/testclient/request', { type: 'forecast15d', city_id: CITY_ID }.to_cbor)

  client.get do |_, payload|
    p CBOR.decode(payload)
  end
rescue SystemExit, Interrupt
  puts "Interrupt caught, client [#{client}] disconnect."
  client.disconnect
rescue StandardError => e
  p e
end
