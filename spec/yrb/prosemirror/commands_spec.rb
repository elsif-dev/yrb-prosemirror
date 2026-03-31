# frozen_string_literal: true

require "spec_helper"

RSpec.describe Yrb::Prosemirror::Commands do
  let(:doc) { Y::Doc.new(gc: false) }
  let(:frag) { doc.get_xml_fragment("content") }

  def populate(content_json)
    Yrb::Prosemirror.json_to_fragment(frag, {
      "type" => "doc",
      "content" => content_json
    })
  end

  def paragraphs
    frag.to_a.map { |el| el.to_a.map(&:to_s).join }
  end

  def fragment_json
    Yrb::Prosemirror.fragment_to_json(frag)
  end

  describe ".replace_text" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Hello world"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Second paragraph"}]}
      ])
    end

    it "replaces text within a paragraph" do
      described_class.replace_text(frag, index: 0, find: "world", replace: "Ruby")
      expect(paragraphs[0]).to eq("Hello Ruby")
    end

    it "preserves other paragraphs" do
      described_class.replace_text(frag, index: 0, find: "Hello", replace: "Hi")
      expect(paragraphs[1]).to eq("Second paragraph")
    end

    it "handles replacement at start" do
      described_class.replace_text(frag, index: 0, find: "Hello", replace: "Hi")
      expect(paragraphs[0]).to eq("Hi world")
    end

    it "handles replacement that changes length" do
      described_class.replace_text(frag, index: 0, find: "Hello world", replace: "Hi")
      expect(paragraphs[0]).to eq("Hi")
    end

    it "raises when index out of range" do
      expect {
        described_class.replace_text(frag, index: 5, find: "x", replace: "y")
      }.to raise_error(ArgumentError, /out of range/)
    end

    it "raises when text not found" do
      expect {
        described_class.replace_text(frag, index: 0, find: "missing", replace: "x")
      }.to raise_error(ArgumentError, /not found/)
    end
  end

  describe ".set_node" do
    before do
      populate([
        {"type" => "heading", "attrs" => {"level" => 1}, "content" => [{"type" => "text", "text" => "Title"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Body text"}]}
      ])
    end

    it "changes heading level surgically" do
      described_class.set_node(frag, index: 0, type: "heading", attrs: {"level" => 2})
      json = fragment_json
      expect(json["content"][0]["attrs"]["level"]).to eq("2")
    end

    it "changes paragraph to heading" do
      described_class.set_node(frag, index: 1, type: "heading", attrs: {"level" => 3})
      json = fragment_json
      expect(json["content"][1]["type"]).to eq("heading")
    end

    it "changes heading to paragraph" do
      described_class.set_node(frag, index: 0, type: "paragraph")
      json = fragment_json
      expect(json["content"][0]["type"]).to eq("paragraph")
    end

    it "changes to blockquote" do
      described_class.set_node(frag, index: 1, type: "blockquote")
      json = fragment_json
      expect(json["content"][1]["type"]).to eq("blockquote")
    end

    it "preserves text content on type change" do
      described_class.set_node(frag, index: 0, type: "paragraph")
      expect(paragraphs[0]).to eq("Title")
    end

    it "preserves other blocks" do
      described_class.set_node(frag, index: 0, type: "paragraph")
      expect(paragraphs[1]).to eq("Body text")
    end

    it "raises when index out of range" do
      expect {
        described_class.set_node(frag, index: 5, type: "paragraph")
      }.to raise_error(ArgumentError, /out of range/)
    end

    it "raises when heading level is missing" do
      expect {
        described_class.set_node(frag, index: 0, type: "heading")
      }.to raise_error(ArgumentError, /level/)
    end
  end

  describe ".insert_content_at" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "First"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Second"}]}
      ])
    end

    it "inserts a paragraph at an index" do
      described_class.insert_content_at(frag, index: 1, blocks: [
        {"type" => "paragraph", "text" => "Inserted"}
      ])
      expect(paragraphs).to eq(["First", "Inserted", "Second"])
    end

    it "inserts at the beginning" do
      described_class.insert_content_at(frag, index: 0, blocks: [
        {"type" => "paragraph", "text" => "Before all"}
      ])
      expect(paragraphs[0]).to eq("Before all")
    end

    it "inserts at the end" do
      described_class.insert_content_at(frag, index: 2, blocks: [
        {"type" => "paragraph", "text" => "After all"}
      ])
      expect(paragraphs.last).to eq("After all")
    end

    it "inserts a heading with level" do
      described_class.insert_content_at(frag, index: 0, blocks: [
        {"type" => "heading", "level" => 2, "text" => "New Heading"}
      ])
      json = fragment_json
      expect(json["content"][0]["type"]).to eq("heading")
      expect(json["content"][0]["attrs"]["level"]).to eq("2")
    end

    it "inserts multiple blocks" do
      described_class.insert_content_at(frag, index: 1, blocks: [
        {"type" => "paragraph", "text" => "A"},
        {"type" => "paragraph", "text" => "B"}
      ])
      expect(paragraphs).to eq(["First", "A", "B", "Second"])
    end

    it "inserts a bullet list" do
      described_class.insert_content_at(frag, index: 0, blocks: [
        {"type" => "bulletList", "items" => ["one", "two"]}
      ])
      json = fragment_json
      expect(json["content"][0]["type"]).to eq("bulletList")
    end

    it "raises for empty blocks" do
      expect {
        described_class.insert_content_at(frag, index: 0, blocks: [])
      }.to raise_error(ArgumentError, /non-empty/)
    end

    it "raises for too many blocks" do
      blocks = 51.times.map { {"type" => "paragraph", "text" => "x"} }
      expect {
        described_class.insert_content_at(frag, index: 0, blocks: blocks)
      }.to raise_error(ArgumentError, /max/)
    end
  end

  describe ".delete_range" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "First"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Second"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Third"}]}
      ])
    end

    it "deletes a single block" do
      described_class.delete_range(frag, from: 1, to: 1)
      expect(paragraphs).to eq(["First", "Third"])
    end

    it "deletes a range of blocks" do
      described_class.delete_range(frag, from: 0, to: 1)
      expect(paragraphs).to eq(["Third"])
    end

    it "deletes all blocks" do
      described_class.delete_range(frag, from: 0, to: 2)
      expect(paragraphs).to eq([])
    end

    it "raises when from > to" do
      expect {
        described_class.delete_range(frag, from: 2, to: 0)
      }.to raise_error(ArgumentError, /must be <= to/)
    end

    it "raises when index out of range" do
      expect {
        described_class.delete_range(frag, from: 0, to: 5)
      }.to raise_error(ArgumentError, /out of range/)
    end
  end

  describe ".set_title" do
    let(:title_frag) { doc.get_xml_fragment("title") }

    before do
      Yrb::Prosemirror.json_to_fragment(title_frag, {
        "type" => "doc",
        "content" => [{"type" => "paragraph", "content" => [{"type" => "text", "text" => "Old Title"}]}]
      })
    end

    it "replaces the title text" do
      described_class.set_title(title_frag, title: "New Title")
      text = title_frag.to_a.first.to_a.map(&:to_s).join
      expect(text).to eq("New Title")
    end

    it "works on empty fragment" do
      empty_frag = doc.get_xml_fragment("empty_title")
      described_class.set_title(empty_frag, title: "Brand New")
      text = empty_frag.to_a.first.to_a.map(&:to_s).join
      expect(text).to eq("Brand New")
    end
  end

  describe "cross-environment fixtures" do
    fixtures = JSON.parse(File.read(File.join(__dir__, "../../fixtures/prosemirror_operations.json")))

    fixtures["operations"].each do |op|
      it "produces expected output for #{op["name"]}" do
        target_frag = if op["command"] == "set_title"
          doc.get_xml_fragment("title_#{op["name"]}")
        else
          frag
        end

        Yrb::Prosemirror.json_to_fragment(target_frag, op["initial"])

        args = op["args"].transform_keys(&:to_sym)
        case op["command"]
        when "replace_text"
          described_class.replace_text(target_frag, **args)
        when "set_node"
          args[:attrs] = args[:attrs]&.transform_keys(&:to_s) if args[:attrs]
          described_class.set_node(target_frag, **args)
        when "insert_content_at"
          described_class.insert_content_at(target_frag, **args)
        when "delete_range"
          described_class.delete_range(target_frag, **args)
        when "set_title"
          described_class.set_title(target_frag, **args)
        end

        result = Yrb::Prosemirror.fragment_to_json(target_frag)
        expect(result["content"]).to eq(op["expected"]["content"])
      end
    end
  end

  describe ".suggest_replace_text" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Hello world"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Second paragraph"}]}
      ])
    end

    it "applies deletion mark to found text" do
      described_class.suggest_replace_text(frag, index: 0, find: "world", replace: "Ruby",
                                           author_id: "user-1", batch_id: "batch-1")
      # The text should still show the original + replacement
      expect(paragraphs[0]).to include("world")
      expect(paragraphs[0]).to include("Ruby")
    end

    it "marks original text with suggestionDelete" do
      described_class.suggest_replace_text(frag, index: 0, find: "world", replace: "Ruby",
                                           author_id: "user-1", batch_id: "batch-1")
      diff = frag[0].to_a.find { |c| c.is_a?(Y::XMLText) }.diff
      has_delete_mark = diff.any? { |c| c.insert == "world" && c.attrs&.key?("suggestionDelete") }
      expect(has_delete_mark).to be(true)
    end

    it "marks replacement text with suggestionAdd" do
      described_class.suggest_replace_text(frag, index: 0, find: "world", replace: "Ruby",
                                           author_id: "user-1", batch_id: "batch-1")
      diff = frag[0].to_a.find { |c| c.is_a?(Y::XMLText) }.diff
      has_add_mark = diff.any? { |c| c.insert == "Ruby" && c.attrs&.key?("suggestionAdd") }
      expect(has_add_mark).to be(true)
    end

    it "raises when text not found" do
      expect {
        described_class.suggest_replace_text(frag, index: 0, find: "missing", replace: "x",
                                             author_id: "user-1", batch_id: "batch-1")
      }.to raise_error(ArgumentError, /not found/)
    end
  end

  describe ".suggest_insert_content_at" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "First"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Second"}]}
      ])
    end

    it "inserts blocks with suggestionBlock attribute" do
      described_class.suggest_insert_content_at(frag, index: 1, blocks: [
        {"type" => "paragraph", "text" => "Inserted"}
      ], author_id: "user-1", batch_id: "batch-1")
      expect(frag.to_a.size).to eq(3)
    end

    it "marks inserted block with suggestionBlock add attribute" do
      described_class.suggest_insert_content_at(frag, index: 1, blocks: [
        {"type" => "paragraph", "text" => "Inserted"}
      ], author_id: "user-1", batch_id: "batch-1")
      inserted_block = frag[1]
      attr = inserted_block.get_attribute("suggestionBlock")
      expect(attr).not_to be_empty
      parsed = JSON.parse(attr)
      expect(parsed["action"]).to eq("add")
      expect(parsed["batchId"]).to eq("batch-1")
    end

    it "marks text in inserted block with suggestionAdd" do
      described_class.suggest_insert_content_at(frag, index: 1, blocks: [
        {"type" => "paragraph", "text" => "Inserted"}
      ], author_id: "user-1", batch_id: "batch-1")
      text_node = frag[1].to_a.find { |c| c.is_a?(Y::XMLText) }
      diff = text_node.diff
      has_add_mark = diff.any? { |c| c.insert == "Inserted" && c.attrs&.key?("suggestionAdd") }
      expect(has_add_mark).to be(true)
    end
  end

  describe ".suggest_delete_range" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "First"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Second"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Third"}]}
      ])
    end

    it "marks blocks with suggestionBlock delete attribute" do
      described_class.suggest_delete_range(frag, from: 0, to: 1, author_id: "user-1", batch_id: "batch-1")
      expect(frag[0].get_attribute("suggestionBlock")).to include("delete")
      expect(frag[1].get_attribute("suggestionBlock")).to include("delete")
      expect(frag[2].get_attribute("suggestionBlock")).to be_nil
    end

    it "marks text in deleted blocks with suggestionDelete" do
      described_class.suggest_delete_range(frag, from: 0, to: 1, author_id: "user-1", batch_id: "batch-1")
      text_node = frag[0].to_a.find { |c| c.is_a?(Y::XMLText) }
      diff = text_node.diff
      has_delete_mark = diff.any? { |c| c.attrs&.key?("suggestionDelete") }
      expect(has_delete_mark).to be(true)
    end

    it "blocks remain present until accepted" do
      described_class.suggest_delete_range(frag, from: 1, to: 1, author_id: "user-1", batch_id: "batch-1")
      expect(frag.to_a.size).to eq(3)
    end
  end

  describe ".suggest_set_node" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Title"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Body"}]}
      ])
    end

    it "sets suggestionFormat attribute" do
      described_class.suggest_set_node(frag, index: 0, type: "heading", attrs: {"level" => 2},
                                       author_id: "user-1", batch_id: "batch-1")
      attr = frag[0].get_attribute("suggestionFormat")
      expect(attr).not_to be_empty
      parsed = JSON.parse(attr)
      expect(parsed["toType"]).to eq("heading")
      expect(parsed["toAttrs"]["level"]).to eq(2)
    end

    it "records the original type and attrs" do
      described_class.suggest_set_node(frag, index: 0, type: "heading", attrs: {"level" => 2},
                                       author_id: "user-1", batch_id: "batch-1")
      attr = frag[0].get_attribute("suggestionFormat")
      parsed = JSON.parse(attr)
      expect(parsed["fromType"]).to eq("paragraph")
    end
  end

  describe ".accept_suggestion on replace_text" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Hello world"}]}
      ])
    end

    it "removes suggestionAdd mark" do
      described_class.suggest_replace_text(frag, index: 0, find: "world", replace: "Ruby",
                                           author_id: "user-1", batch_id: "batch-1")
      described_class.accept_suggestion(frag, batch_id: "batch-1")
      diff = frag[0].to_a.find { |c| c.is_a?(Y::XMLText) }.diff
      # Ruby should not have suggestionAdd mark after accept
      has_marked_ruby = diff.any? { |c| c.insert == "Ruby" && c.attrs&.key?("suggestionAdd") }
      expect(has_marked_ruby).to be(false)
    end

    it "deletes text marked with suggestionDelete" do
      described_class.suggest_replace_text(frag, index: 0, find: "world", replace: "Ruby",
                                           author_id: "user-1", batch_id: "batch-1")
      described_class.accept_suggestion(frag, batch_id: "batch-1")
      # "world" should be gone
      expect(paragraphs[0]).not_to include("world")
      expect(paragraphs[0]).to include("Ruby")
    end

    it "produces same result as direct replace_text" do
      # Set up two identical fragments
      frag2 = doc.get_xml_fragment("content2")
      populate_json = [
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Hello world"}]}
      ]
      Yrb::Prosemirror.json_to_fragment(frag2, {"type" => "doc", "content" => populate_json})

      # One with suggestion workflow, one with direct
      described_class.suggest_replace_text(frag, index: 0, find: "world", replace: "Ruby",
                                           author_id: "user-1", batch_id: "batch-1")
      described_class.accept_suggestion(frag, batch_id: "batch-1")

      described_class.replace_text(frag2, index: 0, find: "world", replace: "Ruby")

      expect(paragraphs[0]).to eq(frag2.to_a.map { |el| el.to_a.map(&:to_s).join }.join)
    end
  end

  describe ".reject_suggestion on replace_text" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Hello world"}]}
      ])
    end

    it "deletes text marked with suggestionAdd" do
      described_class.suggest_replace_text(frag, index: 0, find: "world", replace: "Ruby",
                                           author_id: "user-1", batch_id: "batch-1")
      described_class.reject_suggestion(frag, batch_id: "batch-1")
      # Ruby should be gone
      expect(paragraphs[0]).not_to include("Ruby")
    end

    it "removes suggestionDelete mark" do
      described_class.suggest_replace_text(frag, index: 0, find: "world", replace: "Ruby",
                                           author_id: "user-1", batch_id: "batch-1")
      described_class.reject_suggestion(frag, batch_id: "batch-1")
      diff = frag[0].to_a.find { |c| c.is_a?(Y::XMLText) }.diff
      # "world" should not have mark after reject
      has_marked_world = diff.any? { |c| c.insert == "world" && c.attrs&.key?("suggestionDelete") }
      expect(has_marked_world).to be(false)
    end

    it "restores original text" do
      described_class.suggest_replace_text(frag, index: 0, find: "world", replace: "Ruby",
                                           author_id: "user-1", batch_id: "batch-1")
      described_class.reject_suggestion(frag, batch_id: "batch-1")
      expect(paragraphs[0]).to eq("Hello world")
    end
  end

  describe ".accept_suggestion on insert_content_at" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "First"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Second"}]}
      ])
    end

    it "removes suggestionBlock attribute" do
      described_class.suggest_insert_content_at(frag, index: 1, blocks: [
        {"type" => "paragraph", "text" => "Inserted"}
      ], author_id: "user-1", batch_id: "batch-1")
      described_class.accept_suggestion(frag, batch_id: "batch-1")
      attr = frag[1].get_attribute("suggestionBlock")
      expect(attr).to be_empty
    end

    it "produces same result as direct insert_content_at" do
      frag2 = doc.get_xml_fragment("content2")
      populate_json = [
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "First"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Second"}]}
      ]
      Yrb::Prosemirror.json_to_fragment(frag2, {"type" => "doc", "content" => populate_json})

      described_class.suggest_insert_content_at(frag, index: 1, blocks: [
        {"type" => "paragraph", "text" => "Inserted"}
      ], author_id: "user-1", batch_id: "batch-1")
      described_class.accept_suggestion(frag, batch_id: "batch-1")

      described_class.insert_content_at(frag2, index: 1, blocks: [
        {"type" => "paragraph", "text" => "Inserted"}
      ])

      expect(paragraphs[0]).to eq(frag2.to_a.map { |el| el.to_a.map(&:to_s).join }[0])
      expect(paragraphs[1]).to eq(frag2.to_a.map { |el| el.to_a.map(&:to_s).join }[1])
      expect(paragraphs[2]).to eq(frag2.to_a.map { |el| el.to_a.map(&:to_s).join }[2])
    end
  end

  describe ".reject_suggestion on insert_content_at" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "First"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Second"}]}
      ])
    end

    it "deletes the inserted block" do
      described_class.suggest_insert_content_at(frag, index: 1, blocks: [
        {"type" => "paragraph", "text" => "Inserted"}
      ], author_id: "user-1", batch_id: "batch-1")
      described_class.reject_suggestion(frag, batch_id: "batch-1")
      expect(paragraphs).to eq(["First", "Second"])
    end
  end

  describe ".accept_suggestion on delete_range" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "First"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Second"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Third"}]}
      ])
    end

    it "deletes the blocks marked for deletion" do
      described_class.suggest_delete_range(frag, from: 0, to: 1, author_id: "user-1", batch_id: "batch-1")
      described_class.accept_suggestion(frag, batch_id: "batch-1")
      expect(paragraphs).to eq(["Third"])
    end
  end

  describe ".reject_suggestion on delete_range" do
    before do
      populate([
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "First"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Second"}]},
        {"type" => "paragraph", "content" => [{"type" => "text", "text" => "Third"}]}
      ])
    end

    it "removes deletion marks from text" do
      described_class.suggest_delete_range(frag, from: 1, to: 1, author_id: "user-1", batch_id: "batch-1")
      described_class.reject_suggestion(frag, batch_id: "batch-1")
      attr = frag[1].get_attribute("suggestionBlock")
      expect(attr).to be_empty
    end

    it "preserves all blocks" do
      described_class.suggest_delete_range(frag, from: 0, to: 1, author_id: "user-1", batch_id: "batch-1")
      described_class.reject_suggestion(frag, batch_id: "batch-1")
      expect(paragraphs).to eq(["First", "Second", "Third"])
    end
  end
end
