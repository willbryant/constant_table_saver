#!/usr/bin/env ruby

require 'yaml'

rails_versions = ["5.1.1", "5.0.2".."5.0.3", "4.2.7"].flat_map {|spec| Array(spec).collect {|v| v.gsub /.0(\d)/, '.\\1'}}
rails_envs = YAML.load(File.read("test/database.yml")).keys

rails_envs.each do |env|
  rails_versions.each do |version|
    puts "*"*40
    system "RAILS_ENV=#{env} RAILS_VERSION=#{version} rake" or exit(1)
  end
end
