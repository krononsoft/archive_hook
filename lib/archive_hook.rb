require "archive_hook/version"

module ArchiveHook
  class Error < StandardError; end

  class Archiver
    def initialize(dependencies: {}, archive_date:)
      @dependencies = dependencies
      @archive_date = archive_date
    end

    def call(scope)
      parent = scope.model
      if @dependencies[parent].present?
        parent_ids = scope.or(expiration_scope(parent)).pluck(:id)
        @dependencies[parent].each do |child|
          call(child.where(parent.to_s.foreign_key => parent_ids))
        end
      end
      archive_by_scope(scope.or(expiration_scope(parent)))
    end

    private

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

    def expiration_scope(model)
      model.where("created_at < ?", @archive_date)
    end
  end

  class << self
    def archive(root, archive_date, dependencies)
      Archiver.new(dependencies: dependencies, archive_date: archive_date).call(root.none)
    end
  end
end