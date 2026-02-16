# frozen_string_literal: true

require "json"

RSpec.describe Yrb::Prosemirror do
  describe ".decode_mark_name" do
    it "returns bare mark name for non-overlapping marks" do
      expect(described_class.decode_mark_name("bold")).to eq("bold")
    end

    it "strips hash suffix for overlapping marks" do
      expect(described_class.decode_mark_name("link--ABCD1234")).to eq("link")
    end

    it "handles mark names with hyphens" do
      expect(described_class.decode_mark_name("text-style--ABCD1234")).to eq("text-style")
    end

    it "does not strip suffixes that are not valid 8-char base64" do
      expect(described_class.decode_mark_name("my-mark--short")).to eq("my-mark--short")
    end
  end

  describe ".encode_mark_name" do
    it "returns bare name for marks without attributes" do
      expect(described_class.encode_mark_name("bold", nil)).to eq("bold")
      expect(described_class.encode_mark_name("bold", {})).to eq("bold")
    end

    it "appends hash for marks with attributes" do
      encoded = described_class.encode_mark_name("link", { "href" => "https://example.com" })
      expect(encoded).to match(/\Alink--[a-zA-Z0-9+\/=]{8}\z/)
    end

    it "produces consistent hashes for same attributes" do
      attrs = { "href" => "https://example.com" }
      a = described_class.encode_mark_name("link", attrs)
      b = described_class.encode_mark_name("link", attrs)
      expect(a).to eq(b)
    end

    it "produces different hashes for different attributes" do
      a = described_class.encode_mark_name("link", { "href" => "https://a.com" })
      b = described_class.encode_mark_name("link", { "href" => "https://b.com" })
      expect(a).not_to eq(b)
    end
  end

  describe ".fragment_to_json" do
    it "converts empty fragment to doc JSON" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      json = described_class.fragment_to_json(fragment)
      expect(json).to eq({ "type" => "doc", "content" => [] })
    end

    it "converts fragment with paragraph and plain text" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      para = fragment << "paragraph"
      para.push_text("Hello, World!")
      json = described_class.fragment_to_json(fragment)
      expect(json).to eq({
        "type" => "doc",
        "content" => [{
          "type" => "paragraph",
          "content" => [{ "type" => "text", "text" => "Hello, World!" }]
        }]
      })
    end

    it "converts fragment with element attributes" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      heading = fragment << "heading"
      heading.attr_level = "2"
      heading.push_text("Title")
      json = described_class.fragment_to_json(fragment)
      heading_node = json["content"].first
      expect(heading_node["type"]).to eq("heading")
      expect(heading_node["attrs"]).to eq({ "level" => "2" })
    end

    it "converts nested elements" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      blockquote = fragment << "blockquote"
      para = blockquote << "paragraph"
      para.push_text("Quoted text")
      json = described_class.fragment_to_json(fragment)
      expect(json["content"].first["type"]).to eq("blockquote")
      expect(json.dig("content", 0, "content", 0, "type")).to eq("paragraph")
      expect(json.dig("content", 0, "content", 0, "content", 0, "text")).to eq("Quoted text")
    end
  end

  describe ".json_to_fragment" do
    it "populates fragment from simple paragraph JSON" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      json = {
        "type" => "doc",
        "content" => [{
          "type" => "paragraph",
          "content" => [{ "type" => "text", "text" => "Hello, World!" }]
        }]
      }
      described_class.json_to_fragment(fragment, json)
      expect(fragment.size).to eq(1)
      expect(fragment[0].tag).to eq("paragraph")
      expect(fragment[0][0].to_s).to eq("Hello, World!")
    end

    it "populates fragment with element attributes" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      json = {
        "type" => "doc",
        "content" => [{
          "type" => "heading",
          "attrs" => { "level" => "2" },
          "content" => [{ "type" => "text", "text" => "Title" }]
        }]
      }
      described_class.json_to_fragment(fragment, json)
      heading = fragment[0]
      expect(heading.tag).to eq("heading")
      expect(heading.attrs).to include("level" => "2")
    end

    it "populates nested elements" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      json = {
        "type" => "doc",
        "content" => [{
          "type" => "blockquote",
          "content" => [{
            "type" => "paragraph",
            "content" => [{ "type" => "text", "text" => "Quoted" }]
          }]
        }]
      }
      described_class.json_to_fragment(fragment, json)
      expect(fragment[0].tag).to eq("blockquote")
      expect(fragment[0][0].tag).to eq("paragraph")
    end

    it "populates fragment with formatted text" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      json = {
        "type" => "doc",
        "content" => [{
          "type" => "paragraph",
          "content" => [
            { "type" => "text", "text" => "bold", "marks" => [{ "type" => "bold" }] },
            { "type" => "text", "text" => " normal" }
          ]
        }]
      }
      described_class.json_to_fragment(fragment, json)
      # Verify structure was created (two text nodes in the paragraph)
      para = fragment[0]
      expect(para.tag).to eq("paragraph")
      # There should be two XMLText children
      children = para.to_a
      expect(children.length).to eq(2)
      expect(children[0]).to be_a(Y::XMLText)
      expect(children[1]).to be_a(Y::XMLText)
    end
  end

  describe ".update_fragment" do
    it "replaces existing content" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")

      initial_json = {
        "type" => "doc",
        "content" => [{ "type" => "paragraph", "content" => [{ "type" => "text", "text" => "Old" }] }]
      }
      described_class.json_to_fragment(fragment, initial_json)
      expect(fragment[0][0].to_s).to eq("Old")

      new_json = {
        "type" => "doc",
        "content" => [{ "type" => "paragraph", "content" => [{ "type" => "text", "text" => "New" }] }]
      }
      described_class.update_fragment(fragment, new_json)
      expect(fragment.size).to eq(1)
      expect(fragment[0][0].to_s).to eq("New")
    end

    it "preserves CRDT history (syncable)" do
      doc1 = Y::Doc.new
      fragment1 = doc1.get_xml_fragment("default")
      initial = {
        "type" => "doc",
        "content" => [{ "type" => "paragraph", "content" => [{ "type" => "text", "text" => "Hello" }] }]
      }
      described_class.json_to_fragment(fragment1, initial)

      doc2 = Y::Doc.new
      doc2.sync(doc1.diff(doc2.state))

      updated = {
        "type" => "doc",
        "content" => [{ "type" => "paragraph", "content" => [{ "type" => "text", "text" => "Updated" }] }]
      }
      state_before = doc2.state
      described_class.update_fragment(fragment1, updated)

      update_diff = doc1.diff(state_before)
      doc2.sync(update_diff)

      fragment2 = doc2.get_xml_fragment("default")
      expect(fragment2[0][0].to_s).to eq("Updated")
    end
  end

  describe "round-trip conversion" do
    it "round-trips simple paragraph" do
      json = {
        "type" => "doc",
        "content" => [{
          "type" => "paragraph",
          "content" => [{ "type" => "text", "text" => "Hello, World!" }]
        }]
      }
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      described_class.json_to_fragment(fragment, json)
      result = described_class.fragment_to_json(fragment)
      expect(result).to eq(json)
    end

    it "round-trips heading with attributes" do
      json = {
        "type" => "doc",
        "content" => [{
          "type" => "heading",
          "attrs" => { "level" => "2" },
          "content" => [{ "type" => "text", "text" => "My Heading" }]
        }]
      }
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      described_class.json_to_fragment(fragment, json)
      result = described_class.fragment_to_json(fragment)
      expect(result).to eq(json)
    end

    it "round-trips multiple paragraphs" do
      json = {
        "type" => "doc",
        "content" => [
          { "type" => "paragraph", "content" => [{ "type" => "text", "text" => "First" }] },
          { "type" => "paragraph", "content" => [{ "type" => "text", "text" => "Second" }] }
        ]
      }
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      described_class.json_to_fragment(fragment, json)
      result = described_class.fragment_to_json(fragment)
      expect(result).to eq(json)
    end

    it "round-trips nested blockquote" do
      json = {
        "type" => "doc",
        "content" => [{
          "type" => "blockquote",
          "content" => [{
            "type" => "paragraph",
            "content" => [{ "type" => "text", "text" => "Quoted" }]
          }]
        }]
      }
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("default")
      described_class.json_to_fragment(fragment, json)
      result = described_class.fragment_to_json(fragment)
      expect(result).to eq(json)
    end
  end
end
