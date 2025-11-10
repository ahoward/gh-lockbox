require 'json'
require 'open3'
require 'time'

module Lockbox
  module GitHub
    class GitHubError < StandardError; end
    class NotInRepositoryError < GitHubError; end
    class GitHubCLIError < GitHubError; end

    module_function

    # Stores a secret in GitHub Secrets
    # @param name [String] The secret name (will be prefixed with LOCKBOX_)
    # @param value [String] The secret value
    # @param repo [String, nil] Repository (owner/repo format), nil for current repo
    # @raise [GitHubError] if storing fails
    def store_secret(name, value, repo: nil)
      secret_name = normalize_secret_name(name)

      cmd = ['gh', 'secret', 'set', secret_name]
      cmd += ['--repo', repo] if repo

      _stdout, stderr, status = Open3.capture3(*cmd, stdin_data: value)

      unless status.success?
        raise GitHubError, "Failed to store secret: #{stderr.strip}"
      end

      true
    end

    # Removes a secret from GitHub Secrets
    # @param name [String] The secret name (will be prefixed with LOCKBOX_)
    # @param repo [String, nil] Repository (owner/repo format), nil for current repo
    # @raise [GitHubError] if removal fails
    def remove_secret(name, repo: nil)
      secret_name = normalize_secret_name(name)

      cmd = ['gh', 'secret', 'remove', secret_name]
      cmd += ['--repo', repo] if repo

      _stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        raise GitHubError, "Failed to remove secret: #{stderr.strip}"
      end

      true
    end

    # Lists all secrets in the repository
    # @param repo [String, nil] Repository (owner/repo format), nil for current repo
    # @return [Array<String>] List of secret names (as stored in GitHub)
    # @raise [GitHubError] if listing fails
    def list_secrets(repo: nil)
      cmd = ['gh', 'secret', 'list', '--json', 'name']
      cmd += ['--repo', repo] if repo

      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        raise GitHubError, "Failed to list secrets: #{stderr.strip}"
      end

      begin
        secrets = JSON.parse(stdout)
        # Return secret names as-is (uppercase with underscores)
        secrets
          .map { |s| s['name'] }
          .sort
      rescue JSON::ParserError => e
        raise GitHubError, "Failed to parse secrets list: #{e.message}"
      end
    end

    # Checks if a secret exists
    # @param name [String] The secret name (will be normalized)
    # @param repo [String, nil] Repository (owner/repo format), nil for current repo
    # @return [Boolean] true if secret exists
    def secret_exists?(name, repo: nil)
      normalized = normalize_secret_name(name)
      list_secrets(repo: repo).include?(normalized)
    end

    # Gets the current repository in owner/repo format
    # @return [String] Repository in owner/repo format
    # @raise [NotInRepositoryError] if not in a repository
    def current_repo
      stdout, _stderr, status = Open3.capture3('gh', 'repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner')

      unless status.success?
        raise NotInRepositoryError, "Not in a GitHub repository or gh CLI not configured"
      end

      stdout.strip
    end

    # Waits for a workflow to become available (after pushing)
    # @param workflow [String] Workflow file name
    # @param repo [String, nil] Repository (owner/repo format), nil for current repo
    # @param timeout [Integer] Maximum time to wait in seconds (default: 30)
    # @return [Boolean] true if workflow is available and active
    # @raise [GitHubError] if timeout is reached
    def wait_for_workflow_available(workflow, repo: nil, timeout: 30)
      start_time = Time.now
      loop do
        cmd = ['gh', 'workflow', 'list', '--json', 'path,name,state']
        cmd += ['--repo', repo] if repo

        stdout, _stderr, status = Open3.capture3(*cmd)

        if status.success?
          begin
            workflows = JSON.parse(stdout)
            matching_workflow = workflows.find { |w| w['path'].end_with?(workflow) }
            if matching_workflow && matching_workflow['state'] == 'active'
              return true
            end
          rescue JSON::ParserError
            # Ignore and retry
          end
        end

        if Time.now - start_time > timeout
          raise GitHubError, "Timeout waiting for workflow to become available: #{workflow}"
        end

        sleep 2
      end
    end

    # Triggers a workflow dispatch event
    # @param workflow [String] Workflow file name or ID
    # @param inputs [Hash] Input parameters for the workflow
    # @param repo [String, nil] Repository (owner/repo format), nil for current repo
    # @param ref [String, nil] Branch or tag name to run the workflow from
    # @return [String] Workflow run URL
    # @raise [GitHubError] if triggering fails
    def trigger_workflow(workflow, inputs: {}, repo: nil, ref: nil)
      cmd = ['gh', 'workflow', 'run', workflow]
      cmd += ['--repo', repo] if repo
      cmd += ['--ref', ref] if ref

      inputs.each do |key, value|
        cmd += ['--field', "#{key}=#{value}"]
      end

      _stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        raise GitHubError, "Failed to trigger workflow: #{stderr.strip}"
      end

      # Wait a moment for the workflow to be created
      sleep 1

      # Get the most recent workflow run
      run_id = get_latest_workflow_run(workflow, repo: repo)

      run_id
    end

    # Gets the latest workflow run ID
    # @param workflow [String] Workflow file name
    # @param repo [String, nil] Repository (owner/repo format), nil for current repo
    # @return [String] Workflow run ID
    # @raise [GitHubError] if retrieval fails
    def get_latest_workflow_run(workflow, repo: nil)
      cmd = ['gh', 'run', 'list', '--workflow', workflow, '--limit', '1', '--json', 'databaseId', '-q', '.[0].databaseId']
      cmd += ['--repo', repo] if repo

      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        raise GitHubError, "Failed to get workflow run: #{stderr.strip}"
      end

      run_id = stdout.strip
      if run_id.empty?
        raise GitHubError, "No workflow runs found for #{workflow}"
      end

      run_id
    end

    # Waits for a workflow run to complete
    # @param run_id [String] Workflow run ID
    # @param repo [String, nil] Repository (owner/repo format), nil for current repo
    # @param timeout [Integer] Maximum time to wait in seconds (default: 300)
    # @return [String] Final status (completed, failed, etc.)
    # @raise [GitHubError] if workflow fails or times out
    def wait_for_workflow(run_id, repo: nil, timeout: 300)
      cmd = ['gh', 'run', 'watch', run_id]
      cmd += ['--repo', repo] if repo

      _stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        # Check if it's a failure or timeout
        raise GitHubError, "Workflow failed or timed out: #{stderr.strip}"
      end

      'completed'
    end

    # Gets the logs for a workflow run
    # @param run_id [String] Workflow run ID
    # @param repo [String, nil] Repository (owner/repo format), nil for current repo
    # @return [String] Workflow logs
    # @raise [GitHubError] if retrieval fails
    def get_workflow_logs(run_id, repo: nil)
      cmd = ['gh', 'run', 'view', run_id, '--log']
      cmd += ['--repo', repo] if repo

      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        raise GitHubError, "Failed to get workflow logs: #{stderr.strip}"
      end

      stdout
    end

    # Checks if gh CLI is installed and authenticated
    # @return [Boolean] true if gh CLI is ready
    def gh_ready?
      _stdout, _stderr, status = Open3.capture3('gh', 'auth', 'status')
      status.success?
    end

    # Normalizes a secret name for GitHub Secrets
    # @param name [String] Secret name (e.g., "my-api-key" or "FOO")
    # @return [String] Normalized name (e.g., "MY_API_KEY" or "FOO")
    def normalize_secret_name(name)
      name.upcase.gsub(/[^A-Z0-9]/, '_')
    end

    # Extracts base name from a secret name
    # @param secret_name [String] Secret name (e.g., "MY_API_KEY")
    # @return [String] Base name (e.g., "my-api-key")
    def denormalize_secret_name(secret_name)
      secret_name
        .downcase
        .gsub('_', '-')
    end

    # Gets the PIN secret name for a given secret
    # @param name [String] Base secret name
    # @return [String] PIN secret name
    def pin_secret_name(name)
      base = name.upcase.gsub(/[^A-Z0-9]/, '_')
      "LOCKBOX_#{base}_PIN"
    end

    # Gist-based recovery methods

    def generate_temp_key
      # Generate UUIDv7 (128-bit)
      # Format: timestamp (48 bits) + version (4 bits) + random (74 bits)
      require 'securerandom'

      # Get current timestamp in milliseconds since epoch
      timestamp_ms = (Time.now.to_f * 1000).to_i

      # UUIDv7 format: xxxxxxxx-xxxx-7xxx-yxxx-xxxxxxxxxxxx
      # timestamp_ms (48 bits) + version (4 bits) + random

      uuid = SecureRandom.uuid

      # For simplicity, just use SecureRandom.uuid which gives us good entropy
      # In production, would implement proper UUIDv7 with timestamp ordering
      uuid
    end

    def calculate_key_id(key)
      require 'digest'
      Digest::MD5.hexdigest(key)[0..7]
    end

    def get_current_username
      output = `gh api user --jq '.login' 2>&1`
      unless $?.success?
        raise GitHubCLIError, "Failed to get current username: #{output}"
      end
      output.strip
    end

    def create_recovery_gist(temp_key, secret_names = [])
      key_id = calculate_key_id(temp_key)
      username = get_current_username
      repo = current_repo
      timestamp = Time.now.to_i

      gist_data = {
        "key_id" => key_id,
        "key" => temp_key,
        "secrets" => secret_names,
        "created_at" => Time.now.utc.iso8601,
        "expires_at" => (Time.now + 3600).utc.iso8601  # 1 hour expiry
      }

      # Encrypt gist content with generic key (LOCKBOX_RECOVERY + repo)
      encryption_key = "LOCKBOX_RECOVERY:#{repo}"
      encrypted_content = Lockbox::Crypto.encrypt(JSON.generate(gist_data), encryption_key)

      filename = "gh-lockbox-recovery-#{username}-#{timestamp}.txt"

      # Write to temp file
      require 'tempfile'
      temp_file = Tempfile.new('lockbox-gist')
      begin
        temp_file.write(encrypted_content)
        temp_file.close

        # Create public gist with encrypted content (no secrets exposed)
        output = `gh gist create #{temp_file.path} --public --filename "#{filename}" --desc "gh-lockbox temp recovery key - auto-delete" 2>&1`
        unless $?.success?
          raise GitHubCLIError, "Failed to create gist: #{output}"
        end

        # Extract gist ID from output (URL)
        gist_id = output.strip.split('/').last

        return gist_id
      ensure
        temp_file.unlink
      end
    end

    def delete_gist(gist_id)
      output = `gh gist delete #{gist_id} --yes 2>&1`
      unless $?.success?
        # Don't fail if gist already deleted
        return false unless output.include?("not found")
      end
      true
    end

    def cleanup_old_recovery_gists
      username = get_current_username

      # List recent gists with JSON output to get timestamps
      output = `gh gist list --limit 50 --json id,description,updatedAt 2>&1`
      unless $?.success?
        # Non-fatal, just skip cleanup
        return
      end

      begin
        gists = JSON.parse(output)
      rescue JSON::ParserError
        # Non-fatal, skip cleanup if parsing fails
        return
      end

      # Find gh-lockbox gists
      lockbox_gists = gists.select { |g| g['description']&.include?('gh-lockbox') }

      lockbox_gists.each do |gist|
        begin
          # Parse gist updated time
          updated_at = Time.parse(gist['updatedAt'])
          age_minutes = (Time.now - updated_at) / 60

          # Only delete gists older than 10 minutes (ephemeral keys should be used within seconds)
          if age_minutes > 10
            delete_gist(gist['id'])
          end
        rescue => e
          # Ignore errors during cleanup
        end
      end
    end

    # Locking mechanism using git branches

    # Acquires a lock by creating a lock branch
    # @param lock_name [String] Name of the lock (default: 'recovery')
    # @param timeout [Integer] Maximum time to wait for lock in seconds (default: 300)
    # @param retry_interval [Integer] Time between retries in seconds (default: 5)
    # @return [Boolean] true if lock acquired
    # @raise [GitHubError] if timeout is reached
    def acquire_lock(lock_name: 'recovery', timeout: 300, retry_interval: 5)
      lock_branch = "lockbox-lock-#{lock_name}"
      start_time = Time.now

      loop do
        # Try to create and push lock branch
        stdout, stderr, status = Open3.capture3(
          'git', 'checkout', '-b', lock_branch
        )

        if status.success?
          # Successfully created branch locally, now try to push it
          stdout, stderr, status = Open3.capture3(
            'git', 'push', 'origin', lock_branch
          )

          if status.success?
            # Verify we actually own the lock by checking the commit SHA
            # Get local commit SHA
            local_sha, _, _ = Open3.capture3('git', 'rev-parse', lock_branch)
            local_sha = local_sha.strip

            # Get remote commit SHA
            remote_sha, _, _ = Open3.capture3('git', 'ls-remote', 'origin', lock_branch)
            remote_sha = remote_sha.split.first.to_s.strip

            # Switch back to main
            system('git', 'checkout', 'main', out: File::NULL, err: File::NULL)

            if local_sha == remote_sha && !local_sha.empty?
              # We truly own the lock
              return true
            else
              # Someone else pushed at the same time, retry
              system('git', 'branch', '-D', lock_branch, out: File::NULL, err: File::NULL)
            end
          else
            # Push failed, lock already exists remotely
            # Delete local branch and retry
            system('git', 'checkout', 'main', out: File::NULL, err: File::NULL)
            system('git', 'branch', '-D', lock_branch, out: File::NULL, err: File::NULL)
          end
        else
          # Branch already exists locally, delete it first
          system('git', 'branch', '-D', lock_branch, out: File::NULL, err: File::NULL)
        end

        # Check timeout
        if Time.now - start_time > timeout
          raise GitHubError, "Timeout waiting for lock '#{lock_name}'. Another recovery may be in progress."
        end

        # Wait before retrying
        sleep retry_interval
      end
    end

    # Releases a lock by deleting the lock branch
    # @param lock_name [String] Name of the lock (default: 'recovery')
    # @return [Boolean] true if lock released successfully
    def release_lock(lock_name: 'recovery')
      lock_branch = "lockbox-lock-#{lock_name}"

      # Delete remote lock branch
      stdout, stderr, status = Open3.capture3(
        'git', 'push', 'origin', '--delete', lock_branch
      )

      # Also delete local lock branch if it exists
      system('git', 'branch', '-D', lock_branch, out: File::NULL, err: File::NULL)

      status.success?
    end

    # Checks if a lock is currently held
    # @param lock_name [String] Name of the lock (default: 'recovery')
    # @return [Boolean] true if lock exists
    def lock_held?(lock_name: 'recovery')
      lock_branch = "lockbox-lock-#{lock_name}"

      stdout, stderr, status = Open3.capture3(
        'git', 'ls-remote', '--heads', 'origin', lock_branch
      )

      status.success? && !stdout.strip.empty?
    end
  end
end
