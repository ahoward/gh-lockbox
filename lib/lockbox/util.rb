require 'open3'

module Lockbox
  module Util
    class CommandError < StandardError
      attr_reader :command, :status, :stdout, :stderr

      def initialize(command, status, stdout, stderr)
        @command = command
        @status = status
        @stdout = stdout
        @stderr = stderr

        msg = "Command failed: #{command.join(' ')}\n"
        msg += "Exit status: #{status.exitstatus}\n"
        msg += "STDOUT: #{stdout.strip}\n" unless stdout.strip.empty?
        msg += "STDERR: #{stderr.strip}\n" unless stderr.strip.empty?

        super(msg)
      end
    end

    module_function

    # Execute command and capture stdout/stderr
    # Raises CommandError on non-zero exit
    # @param args [Array] Command and arguments
    # @return [Hash] {status:, stdout:, stderr:}
    def sys!(*args)
      stdout = ''
      stderr = ''
      status = nil

      Open3.popen3(*args) do |stdin, o, e, thread|
        stdin.close

        # Read stdout and stderr concurrently
        out_thread = Thread.new { stdout = o.read }
        err_thread = Thread.new { stderr = e.read }

        out_thread.join
        err_thread.join

        status = thread.value
      end

      if status.success?
        { status: status, stdout: stdout, stderr: stderr }
      else
        raise CommandError.new(args, status, stdout, stderr)
      end
    end

    # Execute command, return false on error (no exception)
    # @param args [Array] Command and arguments
    # @return [Hash, false] {status:, stdout:, stderr:} or false
    def sys(*args)
      sys!(*args)
    rescue CommandError
      false
    end
  end
end
