RSpec.describe ArchiveHook do
  it "has a version number" do
    expect(ArchiveHook::VERSION).not_to be nil
  end

  it "dummy tests" do
    ArchiveHook.create_migration "user"
  end
end
