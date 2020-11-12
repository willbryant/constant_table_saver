# -*- encoding: utf-8 -*-
require File.expand_path('../lib/constant_table_saver/version', __FILE__)

spec = Gem::Specification.new do |gem|
  gem.name         = 'constant_table_saver'
  gem.version      = ConstantTableSaver::VERSION
  gem.summary      = "Caches the records from fixed tables, and provides convenience methods to get them."
  gem.description  = <<-EOF
Loads all records from the table on first use, and thereafter returns the
cached (and frozen) records for all find calls.

Optionally, creates class-level methods you can use to grab the records,
named after the name field you specify.
EOF
  gem.author       = "Will Bryant"
  gem.email        = "will.bryant@gmail.com"
  gem.homepage     = "http://github.com/willbryant/constant_table_saver"
  gem.license      = "MIT"

  gem.executables  = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files        = `git ls-files`.split("\n")
  gem.test_files   = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.require_path = "lib"

  gem.add_dependency "activerecord"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "mysql2"  # you probably want 0.4.10 if testing with old versions of rails, but this gem doesn't care
  gem.add_development_dependency "pg"      # you probably want 0.21.0 if testing with old versions of rails, but this gem doesn't care
  gem.add_development_dependency "sqlite3" # you probably want 1.3.6 if testing with old versions of rails, but this gem doesn't care
  gem.add_development_dependency "byebug"
end
