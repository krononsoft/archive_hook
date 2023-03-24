# frozen_string_literal: true

class ArchiveHookCreate<%= archive_table_name.camelize %> < ActiveRecord::Migration<%= migration_version %>
  def up
    execute("CREATE TABLE <%= archive_table_name %> (LIKE <%= table_name %>)")
  end

  def down
    drop_table :<%= archive_table_name %>
  end
end
