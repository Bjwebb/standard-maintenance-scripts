def disable_issues(repo, message)
  if repo.has_issues
    open_issues = repo.open_issues - repo.rels[:pulls].get.data.size
    if open_issues.zero?
      client.edit_repository(repo.full_name, has_issues: false)
      puts "#{repo.html_url}/settings #{'disabled issues'.bold}"
    else
      puts "#{repo.html_url}/issues #{"issues #{message}".bold}"
    end
  end
end

def disable_projects(repo, message)
  if repo.has_projects
    projects = client.projects(repo.full_name, accept: 'application/vnd.github.inertia-preview+json')
    if projects.none?
      client.edit_repository(repo.full_name, has_projects: false)
      puts "#{repo.html_url}/settings #{'disabled projects'.bold}"
    else
      puts "#{repo.html_url}/issues #{"projects #{message}".bold}"
    end
  end
end

namespace :fix do
  desc 'Protects default branches'
  task :protect_branches do
    headers = {accept: 'application/vnd.github.loki-preview+json'}

    known_contexts = Set.new([
      # Unconfigured.
      [],
      # Configured with Travis.
      ['continuous-integration/travis-ci'],
    ])

    repos.each do |repo|
      contexts = []
      if repo.rels[:hooks].get.data.any?{ |datum| datum.name == 'travis' }
        begin
          # Only enable Travis if Travis is configured.
          client.contents(repo.full_name, path: '.travis.yml')
          contexts << 'continuous-integration/travis-ci'
        rescue Octokit::NotFound
          # Do nothing.
        end
      end

      branches = repo.rels[:branches].get(headers: headers).data

      branches_to_protect = [branches.find{ |branch| branch.name == repo.default_branch }]
      if repo.name == 'standard'
        branches_to_protect << branches.find{ |branch| branch.name == 'latest' }
        branches.each do |branch|
          if branch.name[/\A\d\.\d(?:-dev)?\z/]
            branches_to_protect << branch
          end
        end
      end

      options = headers.merge({
        enforce_admins: true,
        required_status_checks: {
          strict: false,
          contexts: contexts,
        },
        required_pull_request_reviews: nil,
      })

      branches_to_protect.each do |branch|
        branch = client.branch(repo.full_name, branch.name)

        if !branch.protected
          client.protect_branch(repo.full_name, branch.name, options)
          puts "#{repo.html_url}/settings/branches/#{branch.name} #{'protected'.bold}"
        else
          protection = client.branch_protection(repo.full_name, branch.name, headers)

          if (!protection.enforce_admins.enabled ||
              protection.required_status_checks.strict ||
              protection.required_status_checks.contexts != contexts && known_contexts.include?(protection.required_status_checks.contexts) ||
              protection.required_pull_request_reviews)
            messages = []

            if !protection.enforce_admins.enabled
              messages << "check 'Include administrators'"
            end
            if protection.required_status_checks.strict
              messages << "uncheck 'Require branches to be up to date before merging'"
            end
            if protection.required_pull_request_reviews
              messages << "uncheck 'Require pull request reviews before merging'"
            end

            added = contexts - branch.protection.required_status_checks.contexts
            if added.any?
              messages << "added: #{added.join(', ')}"
            end

            removed = branch.protection.required_status_checks.contexts - contexts
            if removed.any?
              messages << "removed: #{removed.join(', ')}"
            end

            client.protect_branch(repo.full_name, branch.name, options)
            puts "#{repo.html_url}/settings/branches/#{branch.name} #{messages.join(' | ').bold}"
          elsif protection.required_status_checks.contexts != contexts
            puts "#{repo.html_url}/settings/branches/#{branch.name} unexpected: #{protection.required_status_checks.contexts.join(', ').bold}"
          end
        end
      end

      expected_protected_branches = branches_to_protect.map(&:name)
      unexpected_protected_branches = branches.select{ |branch| branch.protected && !expected_protected_branches.include?(branch.name) }
      if unexpected_protected_branches.any?
        puts "#{repo.html_url}/settings/branches unexpectedly protects:" 
        unexpected_protected_branches.each do |branch|
          puts "- #{branch.name}"
        end
      end
    end
  end

  desc 'Prepares repositories for archival'
  task :archive_repos do
    if ENV['REPOS']
      repos.each do |repo|
        disable_issues(repo, 'should be reviewed')
        disable_projects(repo, 'should be reviewed')

        if !repo.archived
          puts "#{repo.html_url}/settings #{'archive repository'.bold}"
        end
      end
    else
      abort "You must set the REPOS environment variable to archive repositories."
    end
  end

  desc 'Disables empty wikis and lists repositories with invalid names, unexpected configurations, etc.'
  task :lint_repos do
    repos.each do |repo|
      if repo.has_wiki
        response = Faraday.get("#{repo.html_url}/wiki")
        if response.status == 302 && response.headers['location'] == repo.html_url
          client.edit_repository(repo.full_name, has_wiki: false)
          puts "#{repo.html_url}/settings #{'disabled wiki'.bold}"
        end
      end

      if extension?(repo.name)
        if !repo.name[/\Aocds_\w+_extension\z/]
          puts "#{repo.name} is not a valid extension name"
        end

        disable_issues(repo, 'should be moved and disabled')
        disable_projects(repo, 'should be moved and disabled')
      end

      if repo.private
        puts "#{repo.html_url} is private"
      end

      {
        # The only deployments should be for GitHub Pages.
        deployments: {
          path: ' (deployments)',
          filter: -> (datum) { datum.environment != 'github-pages' },
        },
        # Repositories shouldn't have deploy keys.
        keys: {
          path: '/settings/keys',
        },
      }.each do |rel, config|
        filter = config[:filter] || -> (datum) { true }
        formatter = config[:formatter] || -> (datum) { "- #{datum.inspect}" }

        data = repo.rels[rel].get.data.select(&filter)
        if data.any?
          puts "#{repo.html_url}#{config[:path]}"
          data.each do |datum|
            puts formatter.call(datum)
          end
        end
      end
    end
  end

  desc 'Update extension readmes with template content'
  task :update_readmes do
    basedir = variables('BASEDIR')[0]

    template = <<-END

## Issues

Report issues for this extension in the [ocds-extensions repository](https://github.com/open-contracting/ocds-extensions/issues), putting the extension's name in the issue's title.
    END

    updated = []

    paths = Dir[basedir] + Dir[File.join(basedir, '*')]

    paths.each do |path|
      repo_name = File.basename(path)

      if Dir.exist?(path) && extension?(repo_name)
        readme_path = File.join(path, 'README.md')
        content = File.read(readme_path)

        if !content[template]
          if !content.end_with?("\n")
            content << "\n"
          end

          content << template
          updated << repo_name

          File.open(readme_path, 'w') do |f|
            f.write(content)
          end
        end
      end
    end

    if updated.any?
      puts "updated: #{updated.join(' ')}"
    end
  end

  desc 'Update extension.json to new format'
  task :update_extension_jsons do
    basedir = variables('BASEDIR')[0]

    updated = []

    paths = Dir[basedir] + Dir[File.join(basedir, '*')]

    paths.each do |path|
      repo_name = File.basename(path)

      if Dir.exist?(path) && extension?(repo_name)
        file_path = File.join(path, 'extension.json')
        content = JSON.load(File.read(file_path))

        %w(name description).each do |field|
          if String === content[field]
            content[field] = { 'en' => content[field] }
          end
        end

        if String === content['compatibility']
          content['compatibility'] = case content['compatibility']
          when /\A>=1\.1/
            ['1.1']
          when /\A>=1\.0/
            ['1.0', '1.1']
          else
            raise "unexpected compatibility '#{content['compatibility']}'"
          end
        end

        if content.key?('dependencies') && content['dependencies'].empty?
          content.delete('dependencies')
        end

        if !content.key?('documentationUrl')
          content['documentationUrl'] = { 'en' => "https://github.com/open-contracting/#{repo_name}" }
        end

        File.open(file_path, 'w') do |f|
          f.write(JSON.pretty_generate(content) + "\n")
        end
      end
    end

    if updated.any?
      puts "updated: #{updated.join(' ')}"
    end
  end
end
