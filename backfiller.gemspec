# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name = 'backfiller'
  spec.version = '0.1.1'
  spec.authors = ['Andriy Yanko']
  spec.email = ['andriy.yanko@railsware.com']

  spec.summary = 'Backfiller for null database columns'
  spec.homepage = 'https://github.com/railsware/backfiller'
  spec.license = 'MIT'

  spec.required_ruby_version = '>= 2.7.0'

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'activerecord', '>= 6.0.0'

  spec.add_development_dependency 'bundler', '~> 2.2.0'
  spec.add_development_dependency 'rake', '~> 13.0.0'
  spec.add_development_dependency 'rspec', '~> 3.10.0'
  spec.add_development_dependency 'rubocop', '~> 1.18.0'

  spec.add_development_dependency 'pg', '~> 1.2.0'
end
