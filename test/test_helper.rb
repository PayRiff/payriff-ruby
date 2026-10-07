# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "socket"
require "payriff"

class MockServer
  Request = Struct.new(:method, :url, :headers, :body) do
    def json
      JSON.parse(body)
    end
  end

  attr_reader :requests

  def self.instance
    @instance ||= new
  end

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @stubs = {}
    @requests = []
    @mutex = Mutex.new
    Thread.new { loop { handle(@server.accept) } }
  end

  def url
    "http://127.0.0.1:#{@server.addr[1]}"
  end

  def reset
    @mutex.synchronize do
      @stubs.clear
      @requests.clear
    end
  end

  def stub(method, url, status: 200, headers: {}, body: nil)
    raw = body.is_a?(String) ? body : (body.nil? ? "" : JSON.generate(body))
    @mutex.synchronize { @stubs["#{method} #{url}"] = [status, headers, raw.b] }
  end

  def ok(method, url, payload)
    stub(method, url, body: { "code" => "00000", "message" => "Operation performed successfully", "payload" => payload })
  end

  def last
    @mutex.synchronize { @requests.last }
  end

  def client(**options)
    Payriff::Client.new(app_key: "app-key", merchant_id: "ES1000000", base_url: url, **options)
  end

  private

  def handle(socket)
    method, target = socket.gets.to_s.split(" ")
    headers = {}
    while (line = socket.gets) && line != "\r\n"
      name, value = line.split(":", 2)
      headers[name.strip.downcase] = value.to_s.strip
    end
    body = socket.read(headers["content-length"].to_i).to_s
    stub = @mutex.synchronize do
      @requests << Request.new(method, target, headers, body)
      @stubs["#{method} #{target}"] || @stubs["#{method} #{target.split('?').first}"]
    end
    status, extra, raw = stub || [404, {}, ""]
    response = +"HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{raw.bytesize}\r\nConnection: close\r\n"
    extra.each { |k, v| response << "#{k}: #{v}\r\n" }
    socket.write(response << "\r\n" << raw)
  rescue IOError, SystemCallError
    nil
  ensure
    socket.close
  end
end

class PayriffTest < Minitest::Test
  def setup
    @server = MockServer.instance
    @server.reset
  end

  def ok_body(payload)
    { "code" => "00000", "message" => "Operation performed successfully", "payload" => payload }
  end
end