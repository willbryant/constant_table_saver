module ConstantTableSaver
  module BaseMethods
    def constant_table
      class <<self
        def find(*args)
          options = args.extract_options!
          return super unless options.blank? || options.all? {|k, v| v.nil?}

          @cached_records ||= super(:all).each(&:freeze)
          @cached_records_by_id ||= @cached_records.index_by {|record| record.id.to_param}

          case args.first
            when :first then @cached_records.first
            when :last  then @cached_records.last
            when :all   then @cached_records.dup # shallow copy of the array
            else
              expects_array = args.first.kind_of?(Array)
              return args.first if expects_array && args.first.empty?
              ids = expects_array ? args.first : args
              ids = ids.flatten.compact.uniq

              case ids.size
                when 0
                  raise RecordNotFound, "Couldn't find #{name} without an ID"
                when 1
                  result = @cached_records_by_id[ids.first.to_param]
                  expects_array ? [result] : result
                else
                  ids.collect {|id| @cached_records_by_id[id.to_param]}
              end
          end
        end
        
        # Resets the cached records.  Remember that this only affects this process, so while this
        # is useful for running tests, it's unlikely that you can use this in production - you
        # would need to call it on every Rails instance on every Rails server.  Don't use this
        # plugin on if the table isn't really constant!
        def reset_cache
          @cached_records = @cached_records_by_id = nil
        end
      end
    end
  end
end
