require 'io/console'

module Lockbox
  module Pin
    class PinMismatchError < StandardError; end

    module_function

    # Prompts for a PIN with masked input (shows * for each digit)
    # @param prompt [String] The prompt message to display
    # @param mask_char [String] Character to display for each input character (default: '*')
    # @return [String] The entered PIN
    def prompt_pin(prompt = "Enter PIN: ", mask_char: '*')
      $stderr.print prompt
      $stderr.flush

      pin = ''

      begin
        $stdin.raw do |io|
          loop do
            char = io.getc

            case char
            when "\r", "\n"
              # Enter key pressed - finish input
              $stderr.puts
              break
            when "\u0003"
              # Ctrl-C pressed
              $stderr.puts
              raise Interrupt
            when "\u007F", "\b"
              # Backspace or Delete pressed
              unless pin.empty?
                pin.chop!
                # Clear the last mask character
                $stderr.print "\b \b"
                $stderr.flush
              end
            else
              # Regular character - add to PIN and show mask
              pin += char
              $stderr.print mask_char
              $stderr.flush
            end
          end
        end
      rescue Interrupt
        $stderr.puts "\nAborted."
        exit 1
      end

      pin
    end

    # Prompts for a PIN with confirmation (asks twice and ensures they match)
    # @param prompt [String] The initial prompt message
    # @param confirm_prompt [String] The confirmation prompt message
    # @param max_attempts [Integer] Maximum number of attempts allowed (default: 3)
    # @return [String] The confirmed PIN
    # @raise [PinMismatchError] if PINs don't match after max attempts
    def prompt_pin_with_confirmation(
      prompt = "Enter PIN: ",
      confirm_prompt = "Confirm PIN: ",
      max_attempts: 3
    )
      attempts = 0

      loop do
        attempts += 1

        if attempts > max_attempts
          raise PinMismatchError, "PINs did not match after #{max_attempts} attempts"
        end

        pin1 = prompt_pin(prompt)
        pin2 = prompt_pin(confirm_prompt)

        if pin1 == pin2
          return pin1
        else
          $stderr.puts "❌ PINs do not match. Please try again."
          $stderr.puts
        end
      end
    end

    # Prompts for secret value with hidden input (no visual feedback)
    # @param prompt [String] The prompt message to display
    # @return [String] The entered secret
    def prompt_secret(prompt = "Enter secret value: ")
      $stderr.print prompt
      $stderr.flush

      begin
        # Handle both TTY (interactive) and piped input
        if $stdin.tty?
          # Interactive mode - hide input
          secret = $stdin.noecho(&:gets)
          $stderr.puts
        else
          # Piped input - just read normally
          secret = $stdin.gets
        end
        secret&.chomp || ''
      rescue Interrupt
        $stderr.puts "\nAborted."
        exit 1
      end
    end

    # Validates PIN format (basic validation)
    # @param pin [String] The PIN to validate
    # @param min_length [Integer] Minimum PIN length (default: 4)
    # @return [Boolean] true if valid
    # @raise [ArgumentError] if invalid
    def validate_pin(pin, min_length: 4)
      if pin.nil? || pin.empty?
        raise ArgumentError, "PIN cannot be empty"
      end

      if pin.length < min_length
        raise ArgumentError, "PIN must be at least #{min_length} characters"
      end

      true
    end

    # Validates secret value
    # @param secret [String] The secret to validate
    # @return [Boolean] true if valid
    # @raise [ArgumentError] if invalid
    def validate_secret(secret)
      if secret.nil? || secret.empty?
        raise ArgumentError, "Secret value cannot be empty"
      end

      true
    end

    # Prompts user for confirmation (yes/no)
    # @param prompt [String] The confirmation prompt
    # @param default [Boolean] Default response if user just presses Enter
    # @return [Boolean] true if user confirms
    def confirm(prompt, default: false)
      default_str = default ? "[Y/n]" : "[y/N]"
      $stderr.print "#{prompt} #{default_str}: "
      $stderr.flush

      response = $stdin.gets&.chomp&.downcase || ''

      if response.empty?
        return default
      end

      response.start_with?('y')
    end
  end
end
