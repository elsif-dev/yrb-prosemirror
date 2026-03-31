# frozen_string_literal: true

module Yrb
  module Prosemirror
    # ProseMirror editing commands mirroring TipTap's editor.commands.* API.
    #
    # Each method corresponds to a TipTap command:
    #   set_node          -> editor.commands.setNode(type, attrs)
    #   insert_content_at -> editor.commands.insertContentAt(pos, content)
    #   delete_range      -> editor.commands.deleteRange({from, to})
    #   replace_text      -> (custom: find-and-replace within a paragraph)
    #   set_title         -> (custom: replace title fragment content)
    #
    # Commands operate on Y.Doc XMLFragments using surgical yrs operations.
    module Commands
      MAX_BLOCKS = 50

      module_function

      # Find and replace text within a paragraph.
      #
      # @param fragment [Y::XMLFragment] the content fragment
      # @param index [Integer] 0-based paragraph index
      # @param find [String] exact text to find
      # @param replace [String] replacement text
      # @raise [ArgumentError] if index is out of range or text not found
      # @example
      #   Commands.replace_text(fragment, index: 0, find: "world", replace: "Ruby")
      def replace_text(fragment, index:, find:, replace:)
        children = fragment.to_a
        validate_index!(children, index)

        element = children[index]
        text_node = find_text_node(element)
        current_text = text_node.to_s

        pos = current_text.index(find)
        raise ArgumentError, "Text '#{find[0..49]}' not found in paragraph #{index}" unless pos

        text_node.slice!(pos, find.length)
        text_node.insert(pos, replace)
      end

      # Change the block type of a node at the given index.
      # Mirrors TipTap's editor.commands.setNode(type, attrs).
      #
      # @param fragment [Y::XMLFragment] the content fragment
      # @param index [Integer] 0-based paragraph index
      # @param type [String] new block type (paragraph, heading, blockquote)
      # @param attrs [Hash] attributes (e.g., {"level" => 2} for headings)
      # @raise [ArgumentError] if index is out of range or required attrs missing
      # @example
      #   Commands.set_node(fragment, index: 0, type: "heading", attrs: {"level" => 2})
      def set_node(fragment, index:, type:, attrs: {})
        raise ArgumentError, "Heading level (1-6) required" if type == "heading" && !attrs.key?("level")

        children = fragment.to_a
        validate_index!(children, index)

        element = children[index]
        current_type = element.respond_to?(:tag) ? element.tag : "paragraph"

        # Surgical path: same type heading, just change level attribute
        if current_type == type && type == "heading"
          element.set_attribute("level", attrs["level"].to_s)
          return
        end

        # Rebuild path: extract text, replace single node
        text_content = element.to_a.map(&:to_s).join
        new_node = build_node(type, text_content, attrs)

        json = Yrb::Prosemirror.fragment_to_json(fragment)
        content = json.is_a?(Hash) ? (json["content"] || []) : []
        content[index] = new_node

        children.size.times { fragment.slice!(0) }
        Yrb::Prosemirror.json_to_fragment(fragment, {"type" => "doc", "content" => content})
      end

      # Insert content blocks at a specific index.
      # Mirrors TipTap's editor.commands.insertContentAt(pos, content).
      #
      # @param fragment [Y::XMLFragment] the content fragment
      # @param index [Integer] insert before this index (0 = start, children.size = end)
      # @param blocks [Array<Hash>] block definitions
      # @raise [ArgumentError] if blocks is empty or exceeds MAX_BLOCKS
      # @example
      #   Commands.insert_content_at(fragment, index: 1, blocks: [
      #     {"type" => "paragraph", "text" => "New paragraph"}
      #   ])
      def insert_content_at(fragment, index:, blocks:)
        raise ArgumentError, "Blocks must be a non-empty array" unless blocks.is_a?(Array) && blocks.any?
        raise ArgumentError, "Too many blocks (max #{MAX_BLOCKS})" if blocks.size > MAX_BLOCKS

        new_nodes = blocks.map { |b| block_to_node(b) }

        json = Yrb::Prosemirror.fragment_to_json(fragment)
        content = json.is_a?(Hash) ? (json["content"] || []) : []
        insert_at = [[index.to_i, 0].max, content.size].min

        suffix = content[insert_at..] || []
        (content.size - insert_at).times { fragment.slice!(insert_at) }
        Yrb::Prosemirror.json_to_fragment(fragment, {
          "type" => "doc",
          "content" => new_nodes + suffix
        })
      end

      # Delete a range of blocks from the fragment.
      # Mirrors TipTap's editor.commands.deleteRange({from, to}).
      #
      # @param fragment [Y::XMLFragment] the content fragment
      # @param from [Integer] start index (inclusive)
      # @param to [Integer] end index (inclusive)
      # @raise [ArgumentError] if from > to or indices out of range
      # @example
      #   Commands.delete_range(fragment, from: 0, to: 2)
      def delete_range(fragment, from:, to:)
        raise ArgumentError, "from (#{from}) must be <= to (#{to})" if from > to

        children = fragment.to_a
        if to >= children.size
          raise ArgumentError, "Index #{to} out of range (0-#{children.size - 1})"
        end

        count = to - from + 1
        count.times { fragment.slice!(from) }
      end

      # Set the title by replacing the title fragment content.
      #
      # @param title_fragment [Y::XMLFragment] the title fragment
      # @param title [String] the new title text
      # @example
      #   Commands.set_title(title_fragment, title: "My New Title")
      def set_title(title_fragment, title:)
        title_fragment.to_a.size.times { title_fragment.slice!(0) }

        Yrb::Prosemirror.json_to_fragment(title_fragment, {
          "type" => "doc",
          "content" => [{"type" => "paragraph", "content" => [{"type" => "text", "text" => title}]}]
        })
      end

      # -- Private helpers --

      private_class_method def self.validate_index!(children, index)
        if index < 0 || index >= children.size
          raise ArgumentError, "Paragraph index #{index} out of range (0-#{children.size - 1})"
        end
      end

      private_class_method def self.find_text_node(element)
        text_node = element.to_a.find { |child| child.is_a?(Y::XMLText) }
        raise ArgumentError, "Paragraph has no text content" unless text_node
        text_node
      end

      private_class_method def self.build_node(type, text, attrs = {})
        case type
        when "heading"
          {"type" => "heading", "attrs" => {"level" => attrs["level"].to_i},
           "content" => [{"type" => "text", "text" => text}]}
        when "blockquote"
          {"type" => "blockquote", "content" => [
            {"type" => "paragraph", "content" => [{"type" => "text", "text" => text}]}
          ]}
        else
          {"type" => "paragraph", "content" => [{"type" => "text", "text" => text}]}
        end
      end

      private_class_method def self.block_to_node(block)
        block = block.transform_keys(&:to_s) if block.respond_to?(:transform_keys)
        type = block["type"].to_s

        case type
        when "heading"
          {"type" => "heading", "attrs" => {"level" => (block["level"] || 2).to_i},
           "content" => [{"type" => "text", "text" => block["text"].to_s}]}
        when "bulletList"
          {"type" => "bulletList", "content" => Array(block["items"]).map { |item|
            {"type" => "listItem", "content" => [
              {"type" => "paragraph", "content" => [{"type" => "text", "text" => item.to_s}]}
            ]}
          }}
        when "orderedList"
          {"type" => "orderedList", "content" => Array(block["items"]).map { |item|
            {"type" => "listItem", "content" => [
              {"type" => "paragraph", "content" => [{"type" => "text", "text" => item.to_s}]}
            ]}
          }}
        when "blockquote"
          {"type" => "blockquote", "content" => [
            {"type" => "paragraph", "content" => [{"type" => "text", "text" => block["text"].to_s}]}
          ]}
        else
          {"type" => "paragraph", "content" => [{"type" => "text", "text" => block["text"].to_s}]}
        end
      end
    end
  end
end
