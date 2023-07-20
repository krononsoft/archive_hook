require "archive_hook/version"

module ArchiveHook
  class Error < StandardError; end

  class Archiver
    def initialize(dependencies: {}, archive_date:)
      @dependencies = dependencies
      @archive_date = archive_date
      @processed = []
    end

    def call(scope)
      parent = scope.model
      parent_id_groups = scope.or(expiration_scope(parent)).in_batches.map { |relation| relation.pluck(:id) }
      if @dependencies[parent] && @dependencies[parent][:children].present?
        @dependencies[parent][:children].each do |child|
          if parent_id_groups.present?
            parent_id_groups.each do |parent_ids|
              call(child.unscoped.where(parent.to_s.foreign_key => parent_ids))
            end
          else
            call(child.none)
          end
        end
      end
      parent_id_groups.each do |parent_ids|
        archive_by_scope(parent.unscoped.where(id: parent_ids))
      end
    end

    private

    def archive_by_scope(scope)
      scope_archiver.call(scope)
    end

    def expiration_scope(model)
      return model.none if @processed.include?(model)

      @processed << model
      column = @dependencies[model] && @dependencies[model][:column] || :created_at
      model.where("#{column} < ?", @archive_date)
    end

    def scope_archiver
      @scope_archiver ||= ScopeArchiver.new(dependencies: @dependencies)
    end
  end

  class ScopeArchiver
    def initialize(dependencies: {})
      @dependencies = dependencies
    end

    def call(scope)
      ActiveRecord::Base.connection.execute(Arel.sql(archive_records_sql(scope)))
      scope.delete_all
    end

    private

    def archive_records_sql(scope)
      table_name = scope.table_name
      attributes_list = scope.column_names.join(",")
      <<-SQL
        INSERT INTO #{table_name}_archive (#{attributes_list})
        #{scope.select(attributes_list).to_sql}
      SQL
    end
  end

  class << self
    def archive(root, archive_date, dependencies)
      Archiver.new(dependencies: dependencies, archive_date: archive_date).call(root.none)
    end

    def archive_scope(scope, dependencies = {})
      ScopeArchiver.new(dependencies: dependencies).call(scope)
    end
  end
end