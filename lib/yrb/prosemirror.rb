# frozen_string_literal: true

require "json"
require "digest"
require "base64"
require "y-rb"
require_relative "prosemirror/version"
require_relative "prosemirror/commands"

module Yrb
  # rubocop:disable Metrics/ModuleLength
  module Prosemirror
    class Error < StandardError; end

    MARK_HASH_PATTERN = %r{\A(.+)(--[a-zA-Z0-9+/=]{8})\z}

    def self.decode_mark_name(encoded)
      match = encoded.match(MARK_HASH_PATTERN)
      match ? match[1] : encoded
    end

    def self.encode_mark_name(mark_type, attrs) # rubocop:disable Metrics/AbcSize
      return mark_type if attrs.nil? || attrs.empty?

      # Algorithm inspired by y-prosemirror:
      # 1. SHA256 digest of the JSON-encoded attributes
      # 2. XOR-convolute the 32-byte digest down to 6 bytes
      # 3. Base64 encode the 6 bytes to get an 8-char string
      digest = Digest::SHA256.digest(attrs.to_json).bytes
      n = 6
      (n...digest.length).each do |i|
        digest[i % n] = digest[i % n] ^ digest[i]
      end
      hash = Base64.strict_encode64(digest[0, n].pack("C*"))
      "#{mark_type}--#{hash}"
    end

    def self.fragment_to_json(fragment)
      {
        "type" => "doc",
        "content" => children_to_json(fragment)
      }
    end

    def self.children_to_json(parent)
      result = []
      parent.each do |child|
        case child
        when Y::XMLElement
          result << element_to_json(child)
        when Y::XMLText
          result.concat(xml_text_to_json(child))
        end
      end
      result
    end
    private_class_method :children_to_json

    def self.element_to_json(element)
      node = { "type" => element.tag }

      attrs = element.attrs.dup
      marks_json = attrs.delete("marks")
      node["attrs"] = attrs unless attrs.empty?
      node["marks"] = JSON.parse(marks_json) if marks_json

      content = children_to_json(element)
      node["content"] = content unless content.empty?

      node
    end
    private_class_method :element_to_json

    def self.xml_text_to_json(xml_text) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
      xml_text.diff.map do |chunk|
        text_node = { "type" => "text", "text" => chunk.insert.to_s }
        if chunk.attrs && !chunk.attrs.empty?
          marks = chunk.attrs.map do |encoded_name, value|
            mark = { "type" => decode_mark_name(encoded_name) }
            unless value.nil? || (value.is_a?(Hash) && value.empty?)
              mark["attrs"] =
                value
            end
            mark
          end
          text_node["marks"] = marks
        end
        text_node
      end
    end
    private_class_method :xml_text_to_json

    def self.json_to_fragment(fragment, json)
      return unless json["content"]

      json["content"].each { |node_json| write_node(fragment, node_json) }
    end

    def self.write_node(parent, node_json)
      if node_json["type"] == "text"
        write_text_node(parent, node_json)
      else
        write_element_node(parent, node_json)
      end
    end
    private_class_method :write_node

    def self.write_element_node(parent, node_json) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      element = parent << node_json["type"]

      node_json["attrs"]&.each do |key, value|
        element.set_attribute(key, value.to_s)
      end

      if node_json["marks"]
        element.set_attribute("marks", node_json["marks"].to_json)
      end

      return unless node_json["content"]

      node_json["content"].each do |child_json|
        write_node(element, child_json)
      end
    end
    private_class_method :write_element_node

    def self.write_text_node(parent, node_json) # rubocop:disable Metrics/MethodLength
      text_content = node_json["text"] || ""
      marks = node_json["marks"] || []

      text = parent.push_text("")

      if marks.empty?
        text.insert(0, text_content)
      else
        attrs = {}
        marks.each do |mark|
          mark_attrs = mark["attrs"]
          encoded_name = encode_mark_name(mark["type"], mark_attrs)
          attrs[encoded_name] = mark_attrs || {}
        end
        text.insert(0, text_content, attrs)
      end
    end
    private_class_method :write_text_node

    def self.update_fragment(fragment, json)
      fragment.document.transact do
        current_size = fragment.size
        fragment.slice!(0, current_size) if current_size.positive?
        json_to_fragment(fragment, json)
      end
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
