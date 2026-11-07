# frozen_string_literal: true

# Read the literal rather than loading the provider: the gemspec is evaluated
# before this gem's lib/ is on the load path, so requiring it would resolve
# against an installed copy of the gem instead.
version_file = File.expand_path('lib/ruby_llm/providers/claude_code/version.rb', __dir__)
gem_version = File.read(version_file)[/VERSION = '([^']+)'/, 1]

Gem::Specification.new do |spec|
  spec.name = 'ruby_llm-providers-claude_code'
  spec.version = gem_version
  spec.authors = ['Dewayne VanHoozer']
  spec.email = ['dvanhoozer@gmail.com']

  spec.summary = 'RubyLLM provider that drives the Claude Code agent through `claude -p`.'
  spec.description = 'Adds a claude_code provider to RubyLLM. Prompts are written to the Claude Code ' \
                     "CLI's stdin in batch mode and its JSON result is read back from stdout, so the " \
                     'agent (with its own tools, settings and resumable sessions) can be used wherever ' \
                     'RubyLLM expects a model, e.g. `--model claude_code/opus` in aia.'
  spec.homepage = 'https://github.com/madbomber/ruby_llm-providers-claude_code'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob('lib/**/*.rb') + %w[LICENSE.txt README.md CHANGELOG.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby_llm', '>= 2.1', '< 3'
end
