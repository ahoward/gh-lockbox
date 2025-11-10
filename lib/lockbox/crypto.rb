require 'openssl'
require 'base64'
require 'json'
require 'digest'

module Lockbox
  module Crypto
    class EncryptionError < StandardError; end
    class DecryptionError < StandardError; end

    module_function

    # Derives a 32-byte AES key from temp UUIDv7 key
    # @param temp_key [String] Temporary UUIDv7 key (36 chars)
    # @return [String] 32-byte binary key
    def derive_key(temp_key)
      raise ArgumentError, "Temp key cannot be empty" if temp_key.nil? || temp_key.empty?

      # Use SHA-256 to hash the UUID into a 32-byte key
      # SHA-256 always produces exactly 32 bytes (256 bits)
      Digest::SHA256.digest(temp_key)
    end

    # Encrypts data using AES-256-GCM with temp key
    # @param data [String] The secret to encrypt
    # @param temp_key [String] Temporary UUIDv7 key
    # @return [String] Base64-encoded JSON containing encrypted data, IV, and auth tag
    def encrypt(data, temp_key)
      raise ArgumentError, "Data cannot be empty" if data.nil? || data.empty?
      raise ArgumentError, "Temp key cannot be empty" if temp_key.nil? || temp_key.empty?

      begin
        cipher = OpenSSL::Cipher.new('aes-256-gcm')
        cipher.encrypt

        key = derive_key(temp_key)
        cipher.key = key

        # Generate random IV (initialization vector)
        iv = cipher.random_iv

        # Encrypt the data
        encrypted = cipher.update(data) + cipher.final

        # Get authentication tag for GCM mode
        auth_tag = cipher.auth_tag

        # Package everything together as JSON, then base64 encode
        package = {
          'version' => '1',
          'ciphertext' => Base64.strict_encode64(encrypted),
          'iv' => Base64.strict_encode64(iv),
          'auth_tag' => Base64.strict_encode64(auth_tag)
        }

        Base64.strict_encode64(package.to_json)
      rescue => e
        raise EncryptionError, "Failed to encrypt: #{e.message}"
      end
    end

    # Decrypts data using AES-256-GCM with temp key
    # @param encrypted_data [String] Base64-encoded encrypted package
    # @param temp_key [String] Temporary UUIDv7 key
    # @return [String] Decrypted secret
    def decrypt(encrypted_data, temp_key)
      raise ArgumentError, "Encrypted data cannot be empty" if encrypted_data.nil? || encrypted_data.empty?
      raise ArgumentError, "Temp key cannot be empty" if temp_key.nil? || temp_key.empty?

      begin
        # Decode base64 and parse JSON
        package = JSON.parse(Base64.strict_decode64(encrypted_data))

        # Verify version
        unless package['version'] == '1'
          raise DecryptionError, "Unsupported encryption version: #{package['version']}"
        end

        # Extract components
        ciphertext = Base64.strict_decode64(package['ciphertext'])
        iv = Base64.strict_decode64(package['iv'])
        auth_tag = Base64.strict_decode64(package['auth_tag'])

        # Set up cipher for decryption
        decipher = OpenSSL::Cipher.new('aes-256-gcm')
        decipher.decrypt

        key = derive_key(temp_key)
        decipher.key = key
        decipher.iv = iv
        decipher.auth_tag = auth_tag

        # Decrypt
        decrypted = decipher.update(ciphertext) + decipher.final
        decrypted
      rescue JSON::ParserError => e
        raise DecryptionError, "Invalid encrypted data format: #{e.message}"
      rescue OpenSSL::Cipher::CipherError => e
        raise DecryptionError, "Decryption failed - incorrect temp key or corrupted data: #{e.message}"
      rescue => e
        raise DecryptionError, "Failed to decrypt: #{e.message}"
      end
    end

    # Validates that a PIN can successfully decrypt the encrypted data
    # @param encrypted_data [String] Base64-encoded encrypted package
    # @param pin [String] User's PIN to validate
    # @return [Boolean] true if PIN is correct
    def valid_pin?(encrypted_data, pin)
      decrypt(encrypted_data, pin)
      true
    rescue DecryptionError
      false
    end

    # ========================================================================
    # Asymmetric (RSA) + Hybrid Encryption
    # ========================================================================

    # Generates an ephemeral RSA keypair
    # @return [Hash] Hash with :private_key and :public_key (PEM strings)
    def generate_keypair
      rsa = OpenSSL::PKey::RSA.new(2048)
      {
        private_key: rsa.to_pem,
        public_key: rsa.public_key.to_pem
      }
    end

    # Hybrid encryption: RSA encrypts AES key, AES encrypts data
    # @param data [String] The secret to encrypt
    # @param public_key_pem [String] RSA public key in PEM format
    # @return [String] Base64-encoded JSON containing encrypted AES key and encrypted data
    def encrypt_hybrid(data, public_key_pem)
      raise ArgumentError, "Data cannot be empty" if data.nil? || data.empty?
      raise ArgumentError, "Public key cannot be empty" if public_key_pem.nil? || public_key_pem.empty?

      begin
        # Generate random AES-256 key (32 bytes)
        aes_key = OpenSSL::Random.random_bytes(32)

        # Encrypt data with AES-256-GCM
        cipher = OpenSSL::Cipher.new('aes-256-gcm')
        cipher.encrypt
        cipher.key = aes_key
        iv = cipher.random_iv
        encrypted_data = cipher.update(data) + cipher.final
        auth_tag = cipher.auth_tag

        # Encrypt AES key with RSA public key
        public_key = OpenSSL::PKey::RSA.new(public_key_pem)
        encrypted_aes_key = public_key.public_encrypt(aes_key)

        # Package everything
        package = {
          'version' => '2',  # Version 2 = hybrid encryption
          'encrypted_key' => Base64.strict_encode64(encrypted_aes_key),
          'ciphertext' => Base64.strict_encode64(encrypted_data),
          'iv' => Base64.strict_encode64(iv),
          'auth_tag' => Base64.strict_encode64(auth_tag)
        }

        Base64.strict_encode64(package.to_json)
      rescue => e
        raise EncryptionError, "Failed to encrypt (hybrid): #{e.message}"
      end
    end

    # Hybrid decryption: RSA decrypts AES key, AES decrypts data
    # @param encrypted_package [String] Base64-encoded encrypted package
    # @param private_key_pem [String] RSA private key in PEM format
    # @return [String] Decrypted secret
    def decrypt_hybrid(encrypted_package, private_key_pem)
      raise ArgumentError, "Encrypted package cannot be empty" if encrypted_package.nil? || encrypted_package.empty?
      raise ArgumentError, "Private key cannot be empty" if private_key_pem.nil? || private_key_pem.empty?

      begin
        # Decode and parse package
        package = JSON.parse(Base64.strict_decode64(encrypted_package))

        # Verify version
        unless package['version'] == '2'
          raise DecryptionError, "Unsupported encryption version: #{package['version']}"
        end

        # Extract components
        encrypted_aes_key = Base64.strict_decode64(package['encrypted_key'])
        ciphertext = Base64.strict_decode64(package['ciphertext'])
        iv = Base64.strict_decode64(package['iv'])
        auth_tag = Base64.strict_decode64(package['auth_tag'])

        # Decrypt AES key with RSA private key
        private_key = OpenSSL::PKey::RSA.new(private_key_pem)
        aes_key = private_key.private_decrypt(encrypted_aes_key)

        # Decrypt data with AES key
        decipher = OpenSSL::Cipher.new('aes-256-gcm')
        decipher.decrypt
        decipher.key = aes_key
        decipher.iv = iv
        decipher.auth_tag = auth_tag

        decipher.update(ciphertext) + decipher.final
      rescue JSON::ParserError => e
        raise DecryptionError, "Invalid encrypted package format: #{e.message}"
      rescue OpenSSL::PKey::RSAError => e
        raise DecryptionError, "RSA decryption failed: #{e.message}"
      rescue OpenSSL::Cipher::CipherError => e
        raise DecryptionError, "AES decryption failed: #{e.message}"
      rescue => e
        raise DecryptionError, "Failed to decrypt (hybrid): #{e.message}"
      end
    end
  end
end
