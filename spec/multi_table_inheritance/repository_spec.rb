require 'towhee/multi_table_inheritance/repository'

RSpec.describe Towhee::MultiTableInheritance::Repository do
  subject do
    described_class.new(
      adapter: adapter,
      schemas: {
        "Site" => Schema.new("sites"),
        "Blog" => Schema.new("blogs", "Site"),
      },
    )
  end

  let(:site_id) { 1 }
  let(:adapter) { double(:adapter) }

  context "happy path" do
    before do
      query = "select * from entities where id = :id"
      allow(adapter).to receive(:select_one).with(query, id: site_id).
        and_return({"type" => "Blog"})

      query = "select * from blogs where entity_id = :entity_id"
      allow(adapter).to receive(:select_one).with(query, entity_id: site_id).
        and_return({"author" => "Someone"})

      query = "select * from sites where entity_id = :entity_id"
      allow(adapter).to receive(:select_one).with(query, entity_id: site_id).
        and_return({"name" => "My Site"})
    end

    it "loads a record" do
      obj = subject.find(site_id)
      expect(obj).not_to be_nil
      expect(obj).to be_a Blog
      expect(obj.name).to eq "My Site"
      expect(obj.author).to eq "Someone"
    end
  end

  context "invalid type" do
    before do
      query = "select * from entities where id = :id"
      allow(adapter).to receive(:select_one).with(query, id: site_id).
        and_return({"type" => "NonExistent"})
    end

    it "notices missing type early" do
      expect {
        obj = subject.find(site_id)
      }.to raise_error(KeyError, 'key not found: "NonExistent"')
    end
  end

  context "multiple records" do
    let(:ids) { [1, 2] }

    before do
      query = "select * from entities where id in :ids"
      allow(adapter).to receive(:select_all).with(query, id: ids).
        and_return([
          {"id" => 2, "type" => "Site"},
          {"id" => 1, "type" => "Blog"},
        ])

      query = "select * from sites where entity_id in :entity_ids"
      allow(adapter).to receive(:select_all).with(query, entity_id: ids).
        and_return([
          {"entity_id" => 1, "name" => "Blog"},
          {"entity_id" => 2, "name" => "Site"},
        ])

      query = "select * from blogs where entity_id in :entity_ids"
      allow(adapter).to receive(:select_all).with(query, entity_id: ids).
        and_return([
          {"entity_id" => 1, "author" => "Someone"},
        ])
    end

    it "loads a record" do
      objs = subject.find_all(ids)
      expect(objs).not_to be_nil
      expect(objs.size).to eq 2
      objs.sort_by! { |obj| obj.name }
      expect(objs.first).to be_a Blog
      expect(objs.first.name).to eq "Blog"
      expect(objs.last).to be_a Site
      expect(objs.last.name).to eq "Site"
    end
  end

  class Schema < Struct.new(:table_name, :parent_type)
    def load(row)
      # If we passed a symbol-keyed Hash, the receiver could
      # use kwargs to destructure it.  However, typically the receiver
      # will not know about _all_ the keys and will forward some to
      # its parent class.  So maybe the flexibility of String keys
      # is important.
      Object.const_get(row["type"]).new(row)
    end
  end

  class Site
    def initialize(attrs)
      @name = attrs["name"]
    end
    attr_reader :name
  end

  # Doesn't necessarily have to extend Site.
  class Blog
    def initialize(attrs)
      @name = attrs["name"]
      @author = attrs["author"]
    end
    attr_reader :name, :author
  end
end
