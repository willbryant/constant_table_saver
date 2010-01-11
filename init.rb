require 'constant_table_saver'
ActiveRecord::Base.send(:extend, ConstantTableSaver::BaseMethods)
