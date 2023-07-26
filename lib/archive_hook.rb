require "archive_hook/version"

module ArchiveHook
  class ExpireExtension
    def initialize(dependencies:, archive_date:)
      @processed = []
      @dependencies = dependencies
      @archive_date = archive_date
    end

    def call(model)
      return model.none if @processed.include?(model)

      @processed << model
      column = @dependencies[model] && @dependencies[model][:column] || :created_at
      model.where("#{column} < ?", @archive_date)
    end
  end

  class ScopeArchiver
    def initialize(dependencies: {}, scope_extension:)
      @dependencies = dependencies
      @scope_extension = scope_extension
    end

    def call(scope)
      parent = scope.model
      parent_id_groups = scope.or(@scope_extension.call(parent)).in_batches.map { |relation| relation.pluck(:id) }
      archive_children(parent, parent_id_groups)
      parent_id_groups.each do |parent_ids|
        archive_by_scope(parent.unscoped.where(id: parent_ids))
      end
    end

    private

    def archive_children(parent, parent_id_groups)
      return unless @dependencies[parent] && @dependencies[parent][:children].present?

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

    def archive_by_scope(scope)
      ActiveRecord::Base.connection.execute(Arel.sql(archive_records_sql(scope)))
      scope.delete_all
    end

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
      scope_extension = ExpireExtension.new(dependencies: dependencies, archive_date: archive_date)
      ScopeArchiver.new(dependencies: dependencies, scope_extension: scope_extension).call(root.none)
    end

    def archive_scope(scope, dependencies = {})
      ScopeArchiver.new(dependencies: dependencies, scope_extension: ->(model) { model.none }).call(scope)
    end
  end
end
