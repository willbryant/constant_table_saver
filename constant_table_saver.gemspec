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


Compatibility
=============

Currently tested against Rails 2.3.14, 3.0.17, 3.1.8, and 3.2.8.
EOF
  gem.has_rdoc     = false
  gem.author       = "Will Bryant"
  gem.email        = "will.bryant@gmail.com"
  gem.homepage     = "http://github.com/willbryant/constant_table_saver"
  
  gem.executables  = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files        = `git ls-files`.split("\n")
  gem.test_files   = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.require_path = "lib"
  
  gem.add_dependency "activerecord"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "sqlite3"
end
