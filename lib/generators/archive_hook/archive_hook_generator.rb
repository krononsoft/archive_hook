class ArchiveHookGenerator < Rails::Generators::NamedBase
  include Rails::Generators::Migration

  source_root File.expand_path('templates', __dir__)

  def copy_archive_hook_migration
    migration_template "migration.rb", migration_file_name, migration_version: migration_version, archive_table_name: archive_table_name
  end

  def self.next_migration_number(_dir_name)
    Time.now.utc.to_s.tr('^0-9', '')[0..13]
  end

  def migration_file_name
    "db/migrate/create_#{archive_table_name}.rb"
  end

  def archive_table_name
    "#{table_name}_archive"
  end

  def migration_version
    if Rails::VERSION::MAJOR >= 5
      "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
    end
  end
end
