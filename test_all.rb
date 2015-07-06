#!/usr/bin/env ruby

require 'yaml'

rails_versions = ["4.2.0".."4.2.3", "4.1.07".."4.1.12", "4.0.13", "3.2.18"].flat_map {|spec| Array(spec).collect {|v| v.gsub /.0(\d)/, '.\\1'}}
rails_envs = YAML.load(File.read("test/database.yml")).keys

rails_envs.each do |env|
  rails_versions.each do |version|
    puts "*"*40
    system "RAILS_ENV=#{env} RAILS_VERSION=#{version} rake" or exit(1)
  end
end
