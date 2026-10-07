# frozen_string_literal: true

require "json"
require "openssl"

module Payriff
  class Card
    def initialize(pan:, card_holder:, expiry_month:, expiry_year:, cvv:)
      pan = digits(pan, "pan")
      raise ArgumentError, "pan must contain 12-19 digits" unless pan.length.between?(12, 19)

      month = digits(expiry_month, "expiry_month").to_i
      raise ArgumentError, "expiry_month must be 1-12" unless month.between?(1, 12)

      year = digits(expiry_year, "expiry_year")
      year = "20#{year}" if year.length == 2
      raise ArgumentError, "expiry_year must have 2 or 4 digits" unless year.length == 4

      cvv = digits(cvv, "cvv")
      raise ArgumentError, "cvv must contain 3-4 digits" unless cvv.length.between?(3, 4)
      raise ArgumentError, "card_holder is required" if card_holder.nil?

      @payload = JSON.generate(
        "pan" => pan,
        "cardHolder" => card_holder.to_s.strip,
        "expiryYear" => year,
        "expiryMonth" => format("%02d", month),
        "cvv" => cvv
      ).freeze
      @masked = "#{pan[0, 6]}******#{pan[-4, 4]}"
      @expiry = "#{format('%02d', month)}/#{year}"
      freeze
    end

    def to_s
      "#<Payriff::Card #{@masked} #{@expiry}>"
    end
    alias inspect to_s

    def to_json(*args)
      to_s.to_json(*args)
    end

    def marshal_dump
      raise TypeError, "Payriff::Card cannot be serialized"
    end

    def encrypted_payload(public_key)
      CardEncryptor.encrypt(public_key, @payload)
    end

    private

    def digits(value, field)
      raise ArgumentError, "#{field} must contain digits only" if value.nil?

      v = value.to_s.gsub(/[\s-]/, "")
      raise ArgumentError, "#{field} must contain digits only" unless v.match?(/\A[0-9]+\z/)

      v
    end
  end

  module CardEncryptor
    PRODUCTION_KEY =
      "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxRq5a+44T6Dac60XmVRQ/7cpPyFsBnamXbJlRVJk8CnES5Re5tVMohyD0hZr" \
      "3zcQj+bxodYB4zZpQTPlrXvFBC3zz+rXnGlevxBQ6W2d3QC9q8vWH8p3ZOwTO3qVvDSHH9o+hMMRNbJ7kueq/KZlX/F+bjZ23CZw7iXE" \
      "GQT3HYVYnnHsvpaguYDteWBag2sPPLLsVjeB3zhTfQ7OsWp5XTkDuRwLugHPvs6RHLcwGCnodukWyvwUaEUQR/kMGC+RbMsAIVkcLMP5" \
      "csfR3Xo7Gi98+i44iLN00f7gE8QvEmvv8xDspyTAjDEL1a5gK7TijJ3yLG/Bwa1rr1uskYy7lwIDAQAB"

    OAEP = { rsa_padding_mode: "oaep", rsa_oaep_md: "sha256", rsa_mgf1_md: "sha256" }.freeze

    module_function

    def parse_key(base64_or_pem)
      body = base64_or_pem.to_s.gsub(/-----(BEGIN|END) PUBLIC KEY-----|\s/, "")
      key = OpenSSL::PKey.read(body.unpack1("m0"))
      raise ArgumentError, "Invalid RSA public key" unless key.is_a?(OpenSSL::PKey::RSA) && !key.private?

      key
    rescue OpenSSL::PKey::PKeyError, ArgumentError
      raise ArgumentError, "Invalid RSA public key"
    end

    def encrypt(public_key, payload)
      aes_key = OpenSSL::Random.random_bytes(32)
      iv = OpenSSL::Random.random_bytes(12)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = aes_key
      cipher.iv = iv
      ciphertext = cipher.update(payload) + cipher.final + cipher.auth_tag(16)
      secret = public_key.encrypt(aes_key + iv, OAEP)
      { message: [ciphertext].pack("m0"), secret_key: [secret].pack("m0") }
    end
  end
end