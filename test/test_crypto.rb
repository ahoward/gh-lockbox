require 'minitest/autorun'
require_relative '../lib/lockbox'

class TestCrypto < Minitest::Test
  def test_derive_key_returns_32_bytes
    pin = "1234"
    key = Lockbox::Crypto.derive_key(pin)
    assert_equal 32, key.bytesize
  end

  def test_derive_key_raises_on_empty_pin
    assert_raises(ArgumentError) { Lockbox::Crypto.derive_key("") }
    assert_raises(ArgumentError) { Lockbox::Crypto.derive_key(nil) }
  end

  def test_encrypt_returns_base64_string
    data = "my secret value"
    pin = "1234"
    encrypted = Lockbox::Crypto.encrypt(data, pin)

    assert_kind_of String, encrypted
    # Should be base64 encoded
    assert_match(/^[A-Za-z0-9+\/]+=*$/, encrypted)
  end

  def test_encrypt_raises_on_empty_data
    assert_raises(ArgumentError) { Lockbox::Crypto.encrypt("", "1234") }
    assert_raises(ArgumentError) { Lockbox::Crypto.encrypt(nil, "1234") }
  end

  def test_encrypt_raises_on_empty_pin
    assert_raises(ArgumentError) { Lockbox::Crypto.encrypt("data", "") }
    assert_raises(ArgumentError) { Lockbox::Crypto.encrypt("data", nil) }
  end

  def test_encrypt_decrypt_round_trip
    data = "my secret value"
    pin = "1234"

    encrypted = Lockbox::Crypto.encrypt(data, pin)
    decrypted = Lockbox::Crypto.decrypt(encrypted, pin)

    assert_equal data, decrypted
  end

  def test_encrypt_decrypt_with_multiline_data
    data = "line 1\nline 2\nline 3"
    pin = "1234"

    encrypted = Lockbox::Crypto.encrypt(data, pin)
    decrypted = Lockbox::Crypto.decrypt(encrypted, pin)

    assert_equal data, decrypted
  end

  def test_encrypt_decrypt_with_binary_data
    data = "\x00\x01\x02\xFF\xFE\xFD".force_encoding('ASCII-8BIT')
    pin = "1234"

    encrypted = Lockbox::Crypto.encrypt(data, pin)
    decrypted = Lockbox::Crypto.decrypt(encrypted, pin)

    assert_equal data.bytes, decrypted.bytes
  end

  def test_decrypt_fails_with_wrong_pin
    data = "my secret value"
    pin = "1234"
    wrong_pin = "5678"

    encrypted = Lockbox::Crypto.encrypt(data, pin)

    assert_raises(Lockbox::Crypto::DecryptionError) do
      Lockbox::Crypto.decrypt(encrypted, wrong_pin)
    end
  end

  def test_decrypt_fails_with_corrupted_data
    pin = "1234"

    assert_raises(Lockbox::Crypto::DecryptionError) do
      Lockbox::Crypto.decrypt("invalid base64!", pin)
    end
  end

  def test_decrypt_raises_on_empty_data
    assert_raises(ArgumentError) { Lockbox::Crypto.decrypt("", "1234") }
    assert_raises(ArgumentError) { Lockbox::Crypto.decrypt(nil, "1234") }
  end

  def test_decrypt_raises_on_empty_pin
    encrypted = Lockbox::Crypto.encrypt("data", "1234")
    assert_raises(ArgumentError) { Lockbox::Crypto.decrypt(encrypted, "") }
    assert_raises(ArgumentError) { Lockbox::Crypto.decrypt(encrypted, nil) }
  end

  def test_valid_pin_returns_true_for_correct_pin
    data = "my secret"
    pin = "1234"

    encrypted = Lockbox::Crypto.encrypt(data, pin)
    assert Lockbox::Crypto.valid_pin?(encrypted, pin)
  end

  def test_valid_pin_returns_false_for_incorrect_pin
    data = "my secret"
    pin = "1234"
    wrong_pin = "5678"

    encrypted = Lockbox::Crypto.encrypt(data, pin)
    refute Lockbox::Crypto.valid_pin?(encrypted, wrong_pin)
  end

  def test_encrypt_produces_different_output_each_time
    data = "my secret"
    pin = "1234"

    encrypted1 = Lockbox::Crypto.encrypt(data, pin)
    encrypted2 = Lockbox::Crypto.encrypt(data, pin)

    # Different IVs should produce different ciphertexts
    refute_equal encrypted1, encrypted2

    # But both should decrypt to the same value
    assert_equal data, Lockbox::Crypto.decrypt(encrypted1, pin)
    assert_equal data, Lockbox::Crypto.decrypt(encrypted2, pin)
  end

  def test_different_pins_produce_different_keys
    pin1 = "1234"
    pin2 = "5678"

    key1 = Lockbox::Crypto.derive_key(pin1)
    key2 = Lockbox::Crypto.derive_key(pin2)

    refute_equal key1, key2
  end

  def test_same_pin_produces_same_key
    pin = "1234"

    key1 = Lockbox::Crypto.derive_key(pin)
    key2 = Lockbox::Crypto.derive_key(pin)

    assert_equal key1, key2
  end

  def test_encrypt_with_long_data
    data = "a" * 100_000
    pin = "1234"

    encrypted = Lockbox::Crypto.encrypt(data, pin)
    decrypted = Lockbox::Crypto.decrypt(encrypted, pin)

    assert_equal data, decrypted
  end

  def test_encrypt_with_unicode_data
    data = "Hello 世界 🔐 مرحبا"
    pin = "1234"

    encrypted = Lockbox::Crypto.encrypt(data, pin)
    decrypted = Lockbox::Crypto.decrypt(encrypted, pin).force_encoding('UTF-8')

    assert_equal data, decrypted
  end
end
