# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"

module CardKeys
  def self.private_key
    @private_key ||= OpenSSL::PKey::RSA.generate(2048)
  end

  def self.public_base64
    [private_key.public_to_der].pack("m0")
  end

  def self.decrypt(secret_key, encrypted_message)
    key_and_iv = private_key.decrypt(secret_key.unpack1("m0"), Payriff::CardEncryptor::OAEP)
    raise "bad key length #{key_and_iv.bytesize}" unless key_and_iv.bytesize == 44

    data = encrypted_message.unpack1("m0")
    cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
    cipher.key = key_and_iv[0, 32]
    cipher.iv = key_and_iv[32, 12]
    cipher.auth_tag = data[-16..]
    (cipher.update(data[0...-16]) + cipher.final).force_encoding(Encoding::UTF_8)
  end
end

class CardTest < Minitest::Test
  CARD = { pan: "4169 7413 3015 1979", card_holder: " JOHN DOE ", expiry_month: "1", expiry_year: "27", cvv: "123" }.freeze

  def test_encrypted_card_decrypts_with_payriff_scheme
    public_key = Payriff::CardEncryptor.parse_key(CardKeys.public_base64)

    encrypted = Payriff::Card.new(**CARD).encrypted_payload(public_key)

    assert_equal '{"pan":"4169741330151979","cardHolder":"JOHN DOE","expiryYear":"2027","expiryMonth":"01","cvv":"123"}',
                 CardKeys.decrypt(encrypted[:secret_key], encrypted[:message])
  end

  def test_every_call_uses_fresh_key_material
    public_key = Payriff::CardEncryptor.parse_key(CardKeys.public_base64)
    card = Payriff::Card.new(**CARD)

    a = card.encrypted_payload(public_key)
    b = card.encrypted_payload(public_key)

    refute_equal a[:message], b[:message]
    refute_equal a[:secret_key], b[:secret_key]
  end

  def test_parses_base64_and_pem_keys
    key = Payriff::CardEncryptor::PRODUCTION_KEY
    pem = "-----BEGIN PUBLIC KEY-----\n#{key.scan(/.{1,64}/).join("\n")}\n-----END PUBLIC KEY-----\n"

    assert_equal 2048, Payriff::CardEncryptor.parse_key(key).n.num_bits
    assert_equal 2048, Payriff::CardEncryptor.parse_key(pem).n.num_bits
  end

  def test_rejects_non_rsa_and_private_keys
    ec = [OpenSSL::PKey::EC.generate("prime256v1").public_to_der].pack("m0")
    private_der = [CardKeys.private_key.private_to_der].pack("m0")

    [ec, private_der].each do |key|
      assert_equal "Invalid RSA public key", assert_raises(ArgumentError) { Payriff::CardEncryptor.parse_key(key) }.message
    end
  end

  def test_normalizes_input
    card = Payriff::Card.new(pan: "4169-7413-3015-1979", card_holder: "Rəşad", expiry_month: 11, expiry_year: 2027, cvv: "1234")
    public_key = Payriff::CardEncryptor.parse_key(CardKeys.public_base64)
    encrypted = card.encrypted_payload(public_key)

    assert_equal '{"pan":"4169741330151979","cardHolder":"Rəşad","expiryYear":"2027","expiryMonth":"11","cvv":"1234"}',
                 CardKeys.decrypt(encrypted[:secret_key], encrypted[:message])
  end

  {
    { pan: "4169" } => "pan must contain 12-19 digits",
    { pan: "4169741330151979000000" } => "pan must contain 12-19 digits",
    { pan: "4169a41330151979" } => "pan must contain digits only",
    { expiry_month: "13" } => "expiry_month must be 1-12",
    { expiry_month: "0" } => "expiry_month must be 1-12",
    { expiry_year: "202" } => "expiry_year must have 2 or 4 digits",
    { cvv: "12" } => "cvv must contain 3-4 digits",
    { cvv: nil } => "cvv must contain digits only",
    { card_holder: nil } => "card_holder is required"
  }.each_with_index do |(override, message), i|
    define_method("test_rejects_invalid_input_#{i}") do
      error = assert_raises(ArgumentError) { Payriff::Card.new(**CARD, **override) }
      assert_equal message, error.message
    end
  end

  def test_never_exposes_sensitive_data
    card = Payriff::Card.new(**CARD)
    log = StringIO.new
    Logger.new(log).info(card)
    Logger.new(log).info({ card: card })
    output = [card.to_s, card.inspect, "#{card}", [card].inspect, { card: card }.inspect, JSON.generate({ card: card }), log.string].join

    assert_includes output, "416974******1979"
    refute_includes output, "4169741330151979"
    refute_includes output, "123\""
    assert_raises(TypeError) { Marshal.dump(card) }
    assert_predicate card, :frozen?
  end
end