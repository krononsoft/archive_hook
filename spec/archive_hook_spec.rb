require "spec_helper"
require "active_record"

RSpec.describe ArchiveHook do
  it "has a version number" do
    expect(ArchiveHook::VERSION).not_to be nil
  end

  class Board < ActiveRecord::Base
  end

  class Card < ActiveRecord::Base
    belongs_to :board
  end

  class Tag < ActiveRecord::Base
    belongs_to :card
  end

  before(:all) do
    database = 'archive_hook_test'
    Kernel.system("createdb", database)
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: database)
    ActiveRecord::Base.connection.execute <<-SQL
      create table boards (
        id integer PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY, 
        title varchar,
        created_at timestamp
      );
      create table cards (
        id integer PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY, 
        title varchar, 
        board_id integer,
        created_at timestamp,
        foreign key (board_id) REFERENCES boards
      );
      create table tags (
        id integer PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY, 
        title varchar, 
        card_id integer,
        created_at timestamp,
        foreign key (card_id) REFERENCES cards
      );
      create table boards_archive (like boards);
      create table cards_archive (like cards);
      create table tags_archive (like tags);
    SQL
  end

  after(:each) do
    ActiveRecord::Base.connection.execute <<-SQL
      delete from tags;
      delete from tags_archive;
      delete from cards;
      delete from cards_archive;
      delete from boards;
      delete from boards_archive;
    SQL
  end

  after(:all) do
    ActiveRecord::Base.connection.disconnect!
    database = 'archive_hook_test'
    Kernel.system('dropdb', database)
  end

  let(:mapping) { { Board => { children: [Card] }, Card => { children: [Tag] } } }
  let!(:actual_board) { Board.create(title: "Current issues") }
  let!(:actual_card) { Card.create(title: "Create game", board: actual_board) }
  let!(:actual_tag) { Tag.create(title: "r1", card: actual_card) }

  describe ".archive" do
    subject { described_class.archive(Board, 1.day.ago, mapping) }

    context "when everything is actual" do
      it "doesn't clear" do
        expect { subject }.to not_change { Board.count }.from(1)
      end
    end

    context "when there is something outdated" do
      context "just on the root level" do
        let!(:outdated_board) { Board.create(title: "Archive board", created_at: 2.days.ago) }

        it "archives them" do
          expect { subject }.to change { Board.count }.by(-1)
                            .and change { Board.from("boards_archive").count }.by(1)
                            .and not_change { Card.count }
                            .and not_change { Tag.count }
        end
      end

      context "just on the second level" do
        let!(:outdated_tag) { Tag.create(title: "r2", created_at: 2.days.ago) }

        it "archives them" do
          expect { subject }.to not_change { Board.count }
                            .and not_change { Card.count }
                            .and change { Tag.count }.by(-1)
                            .and change { Tag.from("tags_archive").count }.by(1)
        end
      end

      context "just on the first level" do
        let!(:outdated_card) { Card.create(title: "Archive card", created_at: 2.days.ago) }

        it "archives them" do
          expect { subject }.to not_change { Board.count }
                            .and change { Card.count }.by(-1)
                            .and change { Card.from("cards_archive").count }.by(1)
                            .and not_change { Tag.count }
        end
      end

      context "default scope" do
        before(:all) do
          class Card
            default_scope { where("1=0") }
          end
        end

        after(:all) do
          class Card
            default_scope { unscoped }
          end
        end

        let!(:outdated_board) { Board.create(title: "Archive board", created_at: 2.days.ago) }
        let!(:related_to_outdated_card) { Card.create(title: "Related to outdated card", board: outdated_board) }

        it "archives them" do
          expect { subject }.to change { Board.count }.by(-1)
                            .and change { Board.from("boards_archive").count }.by(1)
                            .and change { Card.unscoped.count }.by(-1)
                            .and change { Card.unscoped.from("cards_archive").count }.by(1)
        end
      end

      context "complicated relations" do
        let!(:outdated_board) { Board.create(title: "Archive board", created_at: 2.days.ago) }
        let!(:outdated_card) { Card.create(title: "Archive card", created_at: 2.days.ago) }
        let!(:outdated_tag) { Tag.create(title: "r2", created_at: 2.days.ago) }
        let!(:related_to_outdated_card) { Card.create(title: "Related to outdated card", board: outdated_board) }
        let!(:related_to_actual_card) { Card.create(title: "Related to actual card", board: actual_board) }
        let!(:related_tag) { Tag.create(title: "critical", card: related_to_outdated_card) }

        it "archives them" do
          expect { subject }.to change { Board.count }.by(-1)
                            .and change { Board.from("boards_archive").count }.by(1)
                            .and change { Card.count }.by(-2)
                            .and change { Card.from("cards_archive").count }.by(2)
                            .and change { Tag.count }.by(-2)
                            .and change { Tag.from("tags_archive").count }.by(2)
        end
      end
    end

    context "when archive column is not created_at" do
      let(:mapping) { { Board => { children: [Card], column: :published_at } }  }
      let!(:outdated_board) { Board.create(title: "Archive board", created_at: 2.days.ago, published_at: Time.current) }
      let!(:outdated_card) { Card.create(title: "Archive card", created_at: 2.days.ago) }

      before(:all) do
        ActiveRecord::Base.connection.execute <<-SQL
          alter table boards add column published_at timestamp;
          alter table boards_archive add column published_at timestamp;
        SQL
        Board.reset_column_information
      end

      it "doesn't archive" do
        expect { subject }.to not_change { Board.count }.from(2)
                          .and change { Card.count }.by(-1)
      end

      context "and archive date column is suitable" do
        before(:each) do
          outdated_board.update_attribute(:published_at, 2.days.ago)
        end

        it "archives them" do
          expect { subject }.to change { Board.count }.by(-1)
                            .and change { Card.count }.by(-1)
        end
      end
    end
  end

  describe ".archive_scope" do
    subject { described_class.archive_scope(Board.where(id: ids), mapping) }
    let!(:outdated_board) { Board.create(title: "Archive board", created_at: 2.days.ago) }
    let!(:outdated_card) { Card.create(title: "Archive card", created_at: 2.days.ago) }
    let!(:outdated_tag) { Tag.create(title: "r2", created_at: 2.days.ago) }

    context "when everything is actual" do
      let(:ids) { 0 }

      it "doesn't clear" do
        expect { subject }.to not_change { Board.count }.from(2)
      end
    end

    context "when there are items to archive" do
      let(:ids) { actual_board.id }

      it "archives them" do
        expect { subject }.to change { Board.count }.by(-1)
                          .and change { Board.from("boards_archive").count }.by(1)
                          .and change { Card.count }.by(-1)
                          .and change { Card.from("cards_archive").count }.by(1)
                          .and change { Tag.count }.by(-1)
                          .and change { Tag.from("tags_archive").count }.by(1)
      end
    end
  end

  describe ".dearchive_scope" do
    subject { described_class.restore_scope(Board.where(id: ids), mapping) }
    let!(:outdated_board) { Board.create(title: "Archive board", created_at: 2.days.ago) }
    let!(:outdated_card) { Card.create(title: "Archive card", created_at: 2.days.ago) }
    let!(:outdated_tag) { Tag.create(title: "r2", created_at: 2.days.ago) }

    before(:each) do
      described_class.archive_scope(Board.where(id: actual_board.id), mapping)
    end

    context "when everything is actual" do
      let(:ids) { 0 }

      it "doesn't clear" do
        expect { subject }.to not_change { Board.count }.from(1)
      end
    end

    context "when there are items to dearchive" do
      let(:ids) { actual_board.id }

      it "dearchives them" do
        expect { subject }.to change { Board.count }.by(1)
                          .and change { Board.from("boards_archive").count }.by(-1)
                          .and change { Card.count }.by(1)
                          .and change { Card.from("cards_archive").count }.by(-1)
                          .and change { Tag.count }.by(1)
                          .and change { Tag.from("tags_archive").count }.by(-1)
      end
    end
  end
end
