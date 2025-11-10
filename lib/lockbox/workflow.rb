require 'fileutils'
require 'json'

module Lockbox
  module Workflow
    class WorkflowError < StandardError; end

    module_function

    # Gets the path to the workflow template
    # @return [String] Path to template file
    def template_path
      File.expand_path('../../templates/lockbox-recovery.yml', __dir__)
    end

    # Gets the workflows directory for the current repository
    # @return [String] Path to .github/workflows directory
    def workflows_dir
      File.join(Dir.pwd, '.github', 'workflows')
    end

    # Gets the generic workflow file path
    # @return [String] Path to generic workflow file
    def generic_workflow_path
      File.join(workflows_dir, 'lockbox-recovery.yml')
    end

    # Gets the generic workflow file name (relative to repo root)
    # @return [String] Workflow file name
    def generic_workflow_filename
      'lockbox-recovery.yml'
    end

    # DEPRECATED: Gets the workflow file path for a specific secret
    # @param name [String] Secret name
    # @return [String] Path to workflow file
    def workflow_path(name)
      safe_name = name.downcase.gsub(/[^a-z0-9]+/, '-')
      File.join(workflows_dir, "lockbox-recovery-#{safe_name}.yml")
    end

    # DEPRECATED: Gets the workflow file name for a specific secret (relative to repo root)
    # @param name [String] Secret name
    # @return [String] Workflow file name
    def workflow_filename(name)
      safe_name = name.downcase.gsub(/[^a-z0-9]+/, '-')
      "lockbox-recovery-#{safe_name}.yml"
    end

    # Creates a dynamic workflow file with literal secret names
    # @param secret_names [Array<String>] List of secret names to include
    # @param workflow_name [String] Name for the workflow file (default: lockbox-recovery-temp.yml)
    # @return [String] Path to created workflow file
    # @raise [WorkflowError] if creation fails
    def create_dynamic_workflow(secret_names, workflow_name: 'lockbox-recovery-temp.yml')
      unless File.exist?(template_path)
        raise WorkflowError, "Template file not found: #{template_path}"
      end

      # Read template
      workflow_content = File.read(template_path)

      # Build the env section with literal secret references
      env_lines = secret_names.each_with_index.map do |name, idx|
        "          SECRET_#{idx}: ${{ secrets.#{name} }}"
      end
      env_section = env_lines.join("\n")

      # Replace the ALL_SECRETS line with literal secret references
      workflow_content = workflow_content.sub(
        /^(\s+)ALL_SECRETS: \$\{\{ toJson\(secrets\) \}\}$/,
        env_section
      )

      # Update the Ruby script to use indexed environment variables instead of ALL_SECRETS
      workflow_content = workflow_content.sub(
        /# Parse all secrets from JSON.*?^          end$/m,
        [
          "# Build secrets hash from indexed environment variables",
          "          all_secrets = {}",
          "          secret_names.each_with_index do |name, idx|",
          "            value = ENV[\"SECRET_\#{idx}\"]",
            "            all_secrets[name] = value if value && !value.empty?",
          "          end"
        ].join("\n")
      )

      # Ensure workflows directory exists
      FileUtils.mkdir_p(workflows_dir)

      # Write workflow file
      output_path = File.join(workflows_dir, workflow_name)
      File.write(output_path, workflow_content)

      output_path
    end

    # Creates the generic workflow file (no placeholders, handles all secrets)
    # @return [String] Path to created workflow file
    # @raise [WorkflowError] if creation fails
    def create_generic_workflow
      unless File.exist?(template_path)
        raise WorkflowError, "Template file not found: #{template_path}"
      end

      # Read template (no placeholder replacement needed - it's already generic)
      workflow_content = File.read(template_path)

      # Ensure workflows directory exists
      FileUtils.mkdir_p(workflows_dir)

      # Write workflow file
      output_path = generic_workflow_path
      File.write(output_path, workflow_content)

      output_path
    end

    # DEPRECATED: Creates or updates a workflow file for a specific secret
    # Use create_generic_workflow instead
    # @param name [String] Secret name
    # @return [String] Path to created workflow file
    # @raise [WorkflowError] if creation fails
    def create_workflow(name)
      # For backwards compatibility, just create the generic workflow
      create_generic_workflow
    end

    # Removes a workflow file for a secret
    # @param name [String] Secret name
    # @return [Boolean] true if removed, false if didn't exist
    def remove_workflow(name)
      path = workflow_path(name)

      if File.exist?(path)
        File.delete(path)
        true
      else
        false
      end
    end

    # Checks if the generic workflow exists
    # @return [Boolean] true if workflow exists
    def generic_workflow_exists?
      File.exist?(generic_workflow_path)
    end

    # DEPRECATED: Checks if a workflow exists for a secret
    # Now checks for the generic workflow instead
    # @param name [String] Secret name (ignored)
    # @return [Boolean] true if generic workflow exists
    def workflow_exists?(name = nil)
      generic_workflow_exists?
    end

    # Lists all lockbox recovery workflows
    # @return [Array<String>] List of secret names that have workflows
    def list_workflows
      return [] unless Dir.exist?(workflows_dir)

      Dir.glob(File.join(workflows_dir, 'lockbox-recovery-*.yml'))
        .map { |path| File.basename(path) }
        .select { |filename| filename.start_with?('lockbox-recovery-') }
        .map { |filename| filename.sub(/^lockbox-recovery-/, '').sub(/\.yml$/, '') }
        .sort
    end

    # Extracts encrypted secrets map from workflow logs
    # @param logs [String] Workflow logs
    # @return [Hash, nil] Map of {secret_name => encrypted_blob} or nil if not found
    def extract_encrypted_secrets(logs)
      # Look for JSON output in logs
      # The workflow outputs: { "encrypted_secrets": {"FOO": "blob1", "BAR": "blob2"}, "timestamp": "..." }

      # GitHub Actions logs have format: "job\tstep\t2025-11-09T23:37:06.2013601Z <actual output>"
      # We need to strip the timestamp and extract just the JSON

      json_lines = []
      in_json = false
      previous_line = nil

      logs.each_line do |line|
        # Check if line contains our JSON start
        # Only match "encrypted_secrets" to avoid capturing env var output like "ALL_SECRETS: {"
        if line =~ /"encrypted_secrets"/
          in_json = true
          # Add the previous line (the opening brace) if we have it
          json_lines << previous_line if previous_line
        end

        if in_json
          # GitHub Actions log format: "job<tab>step<tab>timestamp<space>content"
          # We need to extract just the content part after the timestamp
          # First, split by tabs and take everything after the first 2 fields
          parts = line.split("\t", 3)  # Limit split to 3 parts max
          content = parts[2] if parts.length >= 3

          if content
            # Now remove the timestamp from the content
            clean_line = content.sub(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z\s*/, '')
            json_lines << clean_line

            # Check if this is the closing brace
            if clean_line.strip == '}'
              break
            end
          end
        else
          # Store this line in case the next line triggers JSON capture
          parts = line.split("\t", 3)
          content = parts[2] if parts.length >= 3
          if content
            previous_line = content.sub(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z\s*/, '')
          end
        end
      end

      return nil if json_lines.empty?

      begin
        json_str = json_lines.join
        parsed = JSON.parse(json_str)
        parsed['encrypted_secrets']
      rescue JSON::ParserError => e
        # Debug: show what we tried to parse
        $stderr.puts "Failed to parse JSON: #{e.message}"
        $stderr.puts "Attempted to parse: #{json_str[0..200]}..."
        nil
      end
    end

    # DEPRECATED: Extracts single encrypted blob from workflow logs
    # Use extract_encrypted_secrets instead for new code
    # @param logs [String] Workflow logs
    # @return [String, nil] Encrypted blob or nil if not found
    def extract_encrypted_blob(logs)
      # For backwards compatibility, try to extract single secret
      secrets_map = extract_encrypted_secrets(logs)
      return nil unless secrets_map

      # Return the first (and likely only) encrypted blob
      secrets_map.values.first
    end
  end
end
