#!/usr/bin/env ruby

require 'yaml'

rails_versions = ["5.1.1".."5.1.4", "5.0.2".."5.0.6", "4.2.10"].flat_map {|spec| Array(spec).collect {|v| v.gsub /.0(\d)/, '.\\1'}}
rails_envs = YAML.load(File.read("test/database.yml")).keys

rails_versions.each do |version|
  puts "*"*40
  system "RAILS_VERSION=#{version} bundle update rails" or exit(1)

  rails_envs.each do |env|
    system "RAILS_ENV=#{env} bundle exec rake" or exit(2)
  end
end
