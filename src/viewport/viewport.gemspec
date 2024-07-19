# frozen_string_literal: true

require_relative "lib/viewport/version"

Gem::Specification.new do |spec|
  spec.name = "viewport"
  spec.version = Viewport::VERSION
  spec.authors = ["Sharon Dagan"]
  spec.email = ["sharon.dagan@gmail.com"]

  spec.summary = "Viewport"
  spec.description = "Display Unifi Protect H.264 fMP4 and RTSP video streams in a simple, unattended webpage."
  spec.homepage = "https://github.com/j4zzcat"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/j4zzcat/viewport"
  spec.metadata["changelog_uri"] = "https://github.com/j4zzcat/viewport/CHANGLELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  spec.add_dependency "commander", "~> 5.0"
  spec.add_dependency "logging", "~> 2.4"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end