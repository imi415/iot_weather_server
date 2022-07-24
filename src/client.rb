# frozen_string_literal: true

require 'bundler'

Bundler.require

Dotenv.load
Dotenv.require_keys('MOJI_APPCODE', 'IOT_MQTT_HOST', 'IOT_MQTT_PORT', 'IOT_MQTT_SSL')

begin
  client = MQTT::Client.new

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

  client.publish('iot/weather/testclient/request', { type: 'condition', city_id: 10 }.to_cbor)

  _, payload = client.get
  p CBOR.decode(payload)

rescue SystemExit, Interrupt
  puts "Interrupt caught, client [#{client}] disconnect."
  client.disconnect
rescue StandardError => e
  p e
end
