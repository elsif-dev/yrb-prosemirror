# frozen_string_literal: true

require "json"
require "time"

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
        Yrb::Prosemirror.json_to_fragment(fragment, { "type" => "doc", "content" => content })
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
        raise ArgumentError, "Index #{to} out of range (0-#{children.size - 1})" if to >= children.size

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
                                            "content" => [{ "type" => "paragraph",
                                                            "content" => [{ "type" => "text", "text" => title }] }]
                                          })
      end

      # Suggest replacing text within a paragraph with a deletion mark on original text
      # and an add mark on the replacement text.
      #
      # @param fragment [Y::XMLFragment] the content fragment
      # @param index [Integer] 0-based paragraph index
      # @param find [String] exact text to find
      # @param replace [String] replacement text
      # @param author_id [String] ID of the author making the suggestion
      # @param batch_id [String] ID to group related suggestions
      # @raise [ArgumentError] if index is out of range or text not found
      # @example
      #   Commands.suggest_replace_text(fragment, index: 0, find: "world", replace: "Ruby",
      #                                   author_id: "user-1", batch_id: "batch-1")
      def suggest_replace_text(fragment, index:, find:, replace:, author_id:, batch_id:)
        children = fragment.to_a
        validate_index!(children, index)

        element = children[index]
        text_node = find_text_node(element)
        current_text = text_node.to_s
        pos = current_text.index(find)
        raise ArgumentError, "Text '#{find[0..49]}' not found in paragraph #{index}" unless pos

        # Use batchId as the simple string value -- Y.js formatting attributes
        # only support primitives (strings, numbers, booleans, null).

        # Mark existing text for deletion
        text_node.format(pos, find.length, { "suggestionDelete" => batch_id })

        # Insert replacement with add mark
        text_node.insert(pos + find.length, replace, { "suggestionAdd" => batch_id })
      end

      # Suggest inserting content blocks at a specific index with suggestion marks.
      #
      # @param fragment [Y::XMLFragment] the content fragment
      # @param index [Integer] insert before this index
      # @param blocks [Array<Hash>] block definitions
      # @param author_id [String] ID of the author making the suggestion
      # @param batch_id [String] ID to group related suggestions
      # @raise [ArgumentError] if blocks is empty or exceeds MAX_BLOCKS
      # @example
      #   Commands.suggest_insert_content_at(fragment, index: 1, blocks: [
      #     {"type" => "paragraph", "text" => "New paragraph"}
      #   ], author_id: "user-1", batch_id: "batch-1")
      def suggest_insert_content_at(fragment, index:, blocks:, author_id:, batch_id:)
        raise ArgumentError, "Blocks must be a non-empty array" unless blocks.is_a?(Array) && blocks.any?

        # Insert the blocks normally first
        insert_content_at(fragment, index: index, blocks: blocks)

        # Then mark the inserted blocks
        children = fragment.to_a
        block_attr = JSON.generate({ "action" => "add", "authorId" => author_id, "batchId" => batch_id })

        blocks.size.times do |i|
          target = children[index + i]
          next unless target

          target.set_attribute("suggestionBlock", block_attr)

          target.to_a.each do |child|
            next unless child.is_a?(Y::XMLText)

            text_len = child.to_s.length
            child.format(0, text_len, { "suggestionAdd" => batch_id }) if text_len.positive?
          end
        end
      end

      # Suggest deleting a range of blocks.
      #
      # @param fragment [Y::XMLFragment] the content fragment
      # @param from [Integer] start index (inclusive)
      # @param to [Integer] end index (inclusive)
      # @param author_id [String] ID of the author making the suggestion
      # @param batch_id [String] ID to group related suggestions
      # @raise [ArgumentError] if from > to or indices out of range
      # @example
      #   Commands.suggest_delete_range(fragment, from: 0, to: 2, author_id: "user-1", batch_id: "batch-1")
      def suggest_delete_range(fragment, from:, to:, author_id:, batch_id:)
        raise ArgumentError, "from (#{from}) must be <= to (#{to})" if from > to

        children = fragment.to_a
        raise ArgumentError, "Index #{to} out of range (0-#{children.size - 1})" if to >= children.size

        block_attr = JSON.generate({ "action" => "delete", "authorId" => author_id, "batchId" => batch_id })

        (from..to).each do |i|
          element = children[i]
          element.set_attribute("suggestionBlock", block_attr)

          element.to_a.each do |child|
            next unless child.is_a?(Y::XMLText)

            text_len = child.to_s.length
            child.format(0, text_len, { "suggestionDelete" => batch_id }) if text_len.positive?
          end
        end
      end

      # Suggest changing the block type of a node at the given index.
      #
      # @param fragment [Y::XMLFragment] the content fragment
      # @param index [Integer] 0-based paragraph index
      # @param type [String] new block type
      # @param attrs [Hash] attributes for the new type
      # @param author_id [String] ID of the author making the suggestion
      # @param batch_id [String] ID to group related suggestions
      # @raise [ArgumentError] if index is out of range
      # @example
      #   Commands.suggest_set_node(fragment, index: 0, type: "heading", attrs: {"level" => 2},
      #                              author_id: "user-1", batch_id: "batch-1")
      def suggest_set_node(fragment, index:, type:, author_id:, batch_id:, attrs: {})
        children = fragment.to_a
        validate_index!(children, index)

        element = children[index]
        current_type = element.respond_to?(:tag) ? element.tag : "paragraph"
        current_attrs = element.respond_to?(:attrs) ? element.attrs : {}

        format_attr = JSON.generate({
                                      "authorId" => author_id, "batchId" => batch_id,
                                      "fromType" => current_type, "toType" => type,
                                      "fromAttrs" => current_attrs, "toAttrs" => attrs
                                    })

        element.set_attribute("suggestionFormat", format_attr)
      end

      # Accept a suggestion by batch ID, applying all suggested changes.
      #
      # @param fragment [Y::XMLFragment] the content fragment
      # @param batch_id [String] ID of the suggestion batch to accept
      # @example
      #   Commands.accept_suggestion(fragment, batch_id: "batch-1")
      def accept_suggestion(fragment, batch_id:)
        children = fragment.to_a
        indices_to_delete = []

        children.each_with_index do |element, idx|
          # Handle suggestionBlock
          block_attr_raw = element.get_attribute("suggestionBlock")
          if block_attr_raw.present?
            block_attr = JSON.parse(block_attr_raw)
            if block_attr["batchId"] == batch_id
              if block_attr["action"] == "delete"
                indices_to_delete << idx
                next
              else
                # Accept add: remove attribute, keep block
                element.set_attribute("suggestionBlock", nil)
              end
            end
          end

          # Handle suggestionFormat
          format_attr_raw = element.get_attribute("suggestionFormat")
          if format_attr_raw.present?
            format_attr = JSON.parse(format_attr_raw)
            if format_attr["batchId"] == batch_id
              element.set_attribute("suggestionFormat", nil)
              set_node(fragment, index: idx, type: format_attr["toType"], attrs: format_attr["toAttrs"] || {})
            end
          end

          # Handle text marks
          element.to_a.each do |child|
            next unless child.is_a?(Y::XMLText)

            accept_text_marks(child, batch_id)
          end
        end

        # Delete blocks marked for deletion (reverse order to preserve indices)
        indices_to_delete.reverse_each { |i| fragment.slice!(i) }
      end

      # Reject a suggestion by batch ID, reverting all suggested changes.
      #
      # @param fragment [Y::XMLFragment] the content fragment
      # @param batch_id [String] ID of the suggestion batch to reject
      # @example
      #   Commands.reject_suggestion(fragment, batch_id: "batch-1")
      def reject_suggestion(fragment, batch_id:)
        children = fragment.to_a
        indices_to_delete = []

        children.each_with_index do |element, idx|
          # Handle suggestionBlock
          block_attr_raw = element.get_attribute("suggestionBlock")
          if block_attr_raw.present?
            block_attr = JSON.parse(block_attr_raw)
            if block_attr["batchId"] == batch_id
              if block_attr["action"] == "add"
                indices_to_delete << idx
                next
              else
                # Reject delete: remove attribute, keep block
                element.set_attribute("suggestionBlock", nil)
                # Also remove text deletion marks
                element.to_a.each do |child|
                  next unless child.is_a?(Y::XMLText)

                  remove_text_mark(child, "suggestionDelete", batch_id)
                end
              end
            end
          end

          # Handle suggestionFormat
          format_attr_raw = element.get_attribute("suggestionFormat")
          if format_attr_raw.present?
            format_attr = JSON.parse(format_attr_raw)
            element.set_attribute("suggestionFormat", nil) if format_attr["batchId"] == batch_id
          end

          # Handle text marks (for non-block suggestions like replace_text)
          next if block_attr_raw.present? # already handled above

          element.to_a.each do |child|
            next unless child.is_a?(Y::XMLText)

            reject_text_marks(child, batch_id)
          end
        end

        indices_to_delete.reverse_each { |i| fragment.slice!(i) }
      end

      # -- Private helpers --

      private_class_method def self.validate_index!(children, index)
        return unless index.negative? || index >= children.size

        raise ArgumentError, "Paragraph index #{index} out of range (0-#{children.size - 1})"
      end

      private_class_method def self.find_text_node(element)
        text_node = element.to_a.find { |child| child.is_a?(Y::XMLText) }
        raise ArgumentError, "Paragraph has no text content" unless text_node

        text_node
      end

      private_class_method def self.build_node(type, text, attrs = {})
        case type
        when "heading"
          { "type" => "heading", "attrs" => { "level" => attrs["level"].to_i },
            "content" => [{ "type" => "text", "text" => text }] }
        when "blockquote"
          { "type" => "blockquote", "content" => [
            { "type" => "paragraph", "content" => [{ "type" => "text", "text" => text }] }
          ] }
        else
          { "type" => "paragraph", "content" => [{ "type" => "text", "text" => text }] }
        end
      end

      private_class_method def self.block_to_node(block)
        block = block.transform_keys(&:to_s) if block.respond_to?(:transform_keys)
        type = block["type"].to_s

        case type
        when "heading"
          { "type" => "heading", "attrs" => { "level" => (block["level"] || 2).to_i },
            "content" => [{ "type" => "text", "text" => block["text"].to_s }] }
        when "bulletList"
          { "type" => "bulletList", "content" => Array(block["items"]).map do |item|
            { "type" => "listItem", "content" => [
              { "type" => "paragraph", "content" => [{ "type" => "text", "text" => item.to_s }] }
            ] }
          end }
        when "orderedList"
          { "type" => "orderedList", "content" => Array(block["items"]).map do |item|
            { "type" => "listItem", "content" => [
              { "type" => "paragraph", "content" => [{ "type" => "text", "text" => item.to_s }] }
            ] }
          end }
        when "blockquote"
          { "type" => "blockquote", "content" => [
            { "type" => "paragraph", "content" => [{ "type" => "text", "text" => block["text"].to_s }] }
          ] }
        else
          { "type" => "paragraph", "content" => [{ "type" => "text", "text" => block["text"].to_s }] }
        end
      end

      private_class_method def self.accept_text_marks(text_node, batch_id)
        # Remove suggestionAdd marks (text becomes regular)
        remove_text_mark(text_node, "suggestionAdd", batch_id)

        # Delete text with suggestionDelete marks
        delete_text_with_mark(text_node, "suggestionDelete", batch_id)
      end

      private_class_method def self.reject_text_marks(text_node, batch_id)
        # Delete text with suggestionAdd marks (reject the addition)
        delete_text_with_mark(text_node, "suggestionAdd", batch_id)

        # Remove suggestionDelete marks (restore original text)
        remove_text_mark(text_node, "suggestionDelete", batch_id)
      end

      private_class_method def self.remove_text_mark(text_node, mark_name, batch_id)
        chunks = text_node.diff
        offset = 0
        chunks.each do |chunk|
          text = chunk.insert
          len = text.is_a?(String) ? text.length : 0
          if chunk.attrs && chunk.attrs[mark_name]
            mark_value = extract_batch_id(chunk.attrs[mark_name])
            text_node.format(offset, len, { mark_name => nil }) if mark_value == batch_id
          end
          offset += len
        end
      end

      private_class_method def self.delete_text_with_mark(text_node, mark_name, batch_id)
        chunks = text_node.diff
        ranges_to_delete = []
        offset = 0
        chunks.each do |chunk|
          text = chunk.insert
          len = text.is_a?(String) ? text.length : 0
          if chunk.attrs && chunk.attrs[mark_name]
            mark_value = extract_batch_id(chunk.attrs[mark_name])
            ranges_to_delete << { offset: offset, length: len } if mark_value == batch_id
          end
          offset += len
        end

        ranges_to_delete.reverse_each do |range|
          text_node.slice!(range[:offset], range[:length])
        end
      end

      # Extract batchId from a mark value. Handles:
      # - Simple string (the batchId itself -- new format)
      # - Hash with "batchId" key (legacy format)
      # - JSON string with batchId (legacy format)
      private_class_method def self.extract_batch_id(value)
        return value if value.is_a?(String) && !value.start_with?("{")
        return value["batchId"] if value.is_a?(Hash)

        JSON.parse(value)["batchId"]
      rescue JSON::ParserError
        value
      end
    end
  end
end
