require 'active_record/fixtures' # so we can hook it & reset our cache afterwards
require 'active_support/core_ext/object/to_param'

module ConstantTableSaver
  module BaseMethods
    def constant_table(options = {})
      options.assert_valid_keys(:name, :name_prefix, :name_suffix)
      class_attribute :constant_table_options, :instance_writer => false
      self.constant_table_options = options

      @constant_record_methods = nil
      
      if ActiveRecord::VERSION::MAJOR == 4
        extend ActiveRecord4ClassMethods
      else
        extend ActiveRecord5ClassMethods
      end
      extend ClassMethods
      extend NameClassMethods if constant_table_options[:name]
      
      klass = defined?(ActiveRecord::FixtureSet) ? ActiveRecord::FixtureSet : ActiveRecord::Fixtures
      class <<klass
        # normally, create_fixtures method gets called exactly once - but unfortunately, it
        # loads the class and does a #respond_to?, which causes us to load and cache before
        # the new records are added, so we need to reset our cache afterwards.
        def create_fixtures_with_constant_tables(*args)
          create_fixtures_without_constant_tables(*args).tap { ConstantTableSaver.reset_all_caches }
        end
        def reset_cache_with_constant_tables(*args)
          reset_cache_without_constant_tables(*args).tap     { ConstantTableSaver.reset_all_caches }
        end
        alias :create_fixtures_without_constant_tables :create_fixtures
        alias :create_fixtures :create_fixtures_with_constant_tables
        alias :reset_cache_without_constant_tables :reset_cache
        alias :reset_cache :reset_cache_with_constant_tables
      end unless klass.respond_to?(:create_fixtures_with_constant_tables)
    end
  end

  def self.reset_all_caches
    klasses = ActiveRecord::Base.respond_to?(:descendants) ? ActiveRecord::Base.descendants : ActiveRecord::Base.send(:subclasses)
    klasses.each {|klass| klass.reset_constant_record_cache! if klass.respond_to?(:reset_constant_record_cache!)}
  end
  
  module ClassMethods
    # Resets the cached records.  Remember that this only affects this process, so while this
    # is useful for running tests, it's unlikely that you can use this in production - you
    # would need to call it on every Rails instance on every Rails server.  Don't use this
    # plugin on if the table isn't really constant!
    def reset_constant_record_cache!
      @constant_record_methods.each {|method_id| (class << self; self; end;).send(:remove_method, method_id)} if @constant_record_methods
      @cached_records = @cached_records_by_id = @constant_record_methods = @cached_blank_scope = @find_by_sql = nil
    end

    def _to_sql_with_binds(sql, binds)
      if sql.respond_to?(:to_sql)
        # an arel object
        if sql.respond_to?(:ast)
          binds = []
        end

        connection.to_sql(sql, binds)
      else
        # a plain string
        sql
      end
    end

    def relation
      super.tap do |s|
        class << s
          # we implement find_some here because we'd have to use partial string matching to catch
          # this case in find_by_sql, which would be ugly.  (we do the other cases in find_by_sql
          # because it's simpler & the only place to catch things like association find queries.)
          def find_some(ids)
            return super if @values.present? # special cases such as offset and limit
            ids.collect {|id| find_one(id)}
          end
        end
      end
    end
  end

  module ActiveRecord5ClassMethods
    def find_by_sql(sql, binds = [], preparable: nil, &block)
      if ActiveRecord::VERSION::MINOR == 2
        primary_key_bind_param = Arel::Nodes::BindParam.new('')
        attribute_klass = ActiveModel::Attribute
      else
        primary_key_bind_param = Arel::Nodes::BindParam.new
        attribute_klass = ActiveRecord::Attribute
      end

      @find_by_sql ||= {
        :all   => relation.to_sql,
        :id    => relation.where(relation.table[primary_key].eq(primary_key_bind_param)).limit(1).arel,
        :first => relation.order(relation.table[primary_key].asc).limit(1).arel,
        :last  => relation.order(relation.table[primary_key].desc).limit(1).arel,
      }

      @limit_one ||= attribute_klass.with_cast_value("LIMIT", 1, ActiveRecord::Type::Value.new)

      _sql = _to_sql_with_binds(sql, binds)

      if ActiveRecord::VERSION::MINOR == 2
        if binds.empty? # Arel case
          if _sql == @find_by_sql[:all]
            return @cached_records ||= super(relation.to_sql).each(&:freeze)
          elsif _sql == _to_sql_with_binds(@find_by_sql[:first], binds)
            return [relation.to_a.first].compact
          elsif _sql == _to_sql_with_binds(@find_by_sql[:last], binds)
            return [relation.to_a.last].compact
          elsif _sql == _to_sql_with_binds(@find_by_sql[:id], binds)
            @cached_records_by_id ||= relation.to_a.index_by {|record| record.id.to_param}
            id_value = sql.constraints.first.left.right.value.value.to_param
            return [@cached_records_by_id[id_value]].compact
          end
        elsif binds.size == 2 &&
              binds.last == @limit_one &&
              binds.first.is_a?(ActiveRecord::Relation::QueryAttribute) &&
              binds.first.name == primary_key &&
              _sql == _to_sql_with_binds(@find_by_sql[:id], binds) # we have to late-render the find(id) SQL because mysql2 on 4.1 and later requires the bind variables to render the SQL, and errors out with a nil dereference otherwise
              @cached_records_by_id ||= relation.to_a.index_by {|record| record.id.to_param}
              return [@cached_records_by_id[binds.first.value.to_param]].compact
        end
      else
        if binds.empty?
          if _sql == @find_by_sql[:all]
            return @cached_records ||= super(relation.to_sql).each(&:freeze)
          end

        elsif binds.size == 1 &&
              binds.last == @limit_one
          if _sql == _to_sql_with_binds(@find_by_sql[:first], binds)
            return [relation.to_a.first].compact
          elsif _sql == _to_sql_with_binds(@find_by_sql[:last], binds)
            return [relation.to_a.last].compact
          end

        elsif binds.size == 2 &&
              binds.last == @limit_one &&
              binds.first.is_a?(ActiveRecord::Relation::QueryAttribute) &&
              binds.first.name == primary_key &&
              _sql == _to_sql_with_binds(@find_by_sql[:id], binds) # we have to late-render the find(id) SQL because mysql2 on 4.1 and later requires the bind variables to render the SQL, and errors out with a nil dereference otherwise
          @cached_records_by_id ||= relation.to_a.index_by {|record| record.id.to_param}
          return [@cached_records_by_id[binds.first.value.to_param]].compact
        end
      end

      super(sql, binds, preparable: preparable, &block)
    end
  end

  module ActiveRecord4ClassMethods
    def find_by_sql(sql, binds = [])
      @find_by_sql ||= {
        :all   => relation.to_sql,
        :id    => relation.where(relation.table[primary_key].eq(connection.substitute_at(columns_hash[primary_key], 0))).limit(1).
                    tap {|r| r.bind_values += [[columns_hash[primary_key], :undefined]]}. # work around AR 4.1.9-4.1.x (but not 4.2.x) calling nil.first if there's no bind_values
                    arel,
        :first => relation.order(relation.table[primary_key].asc).limit(1).to_sql,
        :last  => relation.order(relation.table[primary_key].desc).limit(1).to_sql,
      }

      if binds.empty?
        _sql = _to_sql_with_binds(sql, binds)

        if _sql == @find_by_sql[:all]
          return @cached_records ||= super(relation.to_sql).each(&:freeze)
        elsif _sql == @find_by_sql[:first]
          return [relation.to_a.first].compact
        elsif _sql == @find_by_sql[:last]
          return [relation.to_a.last].compact
        end

      elsif binds.length == 1 &&
            binds.first.first.is_a?(ActiveRecord::ConnectionAdapters::Column) &&
            binds.first.first.name == primary_key &&
            _to_sql_with_binds(sql, binds) == _to_sql_with_binds(@find_by_sql[:id], binds) # we have to late-render the find(id) SQL because mysql2 on 4.1 and later requires the bind variables to render the SQL, and errors out with a nil dereference otherwise
        @cached_records_by_id ||= relation.to_a.index_by {|record| record.id.to_param}
        return [@cached_records_by_id[binds.first.last.to_param]].compact
      end

      super
    end
  end

  module NameClassMethods
    def define_named_record_methods
      @constant_record_methods = [] # dummy so respond_to? & method_missing don't call us again if reading an attribute causes another method_missing
      @constant_record_methods = all.collect do |record|
        method_name = "#{constant_table_options[:name_prefix]}#{record[constant_table_options[:name]].downcase.gsub(/\W+/, '_')}#{constant_table_options[:name_suffix]}"
        next if method_name.blank?
        (class << self; self; end;).instance_eval { define_method(method_name) { record } }
        method_name.to_sym
      end.compact.uniq
    end
    
    def respond_to?(method_id, include_private = false)
      super || (@constant_record_methods.nil? && @attribute_methods_generated && define_named_record_methods && super)
    end
    
    def method_missing(method_id, *arguments, &block)
      if @constant_record_methods.nil?
        define_named_record_methods
        send(method_id, *arguments, &block) # retry
      else
        super
      end
    end
  end
end

ActiveRecord::Base.send(:extend, ConstantTableSaver::BaseMethods)
