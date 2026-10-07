# frozen_string_literal: true

module Payriff
  class PayriffObject
    RENAMES = { "comissionRate" => :commission_rate, "_final" => :final_state }.freeze

    def self.convert(value)
      case value
      when Hash then new(value)
      when Array then value.map { |v| convert(v) }
      else value
      end
    end

    def self.snake(key)
      RENAMES.fetch(key) do
        key.to_s
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase
           .to_sym
      end
    end

    def initialize(hash)
      @values = {}
      hash.each do |key, value|
        name = self.class.snake(key)
        @values[name] = self.class.convert(value) unless @values.key?(name) && value.nil?
      end
    end

    def [](key)
      @values[key.to_sym]
    end

    def key?(key)
      @values.key?(key.to_sym)
    end

    def keys
      @values.keys
    end

    def to_h
      @values.transform_values { |v| unwrap(v) }
    end

    def ==(other)
      other.is_a?(PayriffObject) && other.to_h == to_h
    end

    def inspect
      "#<#{self.class.name} #{@values.inspect}>"
    end

    FIELD_NAME = /\A(?!to_)[a-z][a-z0-9_]*\z/

    def respond_to_missing?(name, include_private = false)
      @values.key?(name) || super
    end

    def method_missing(name, *args)
      return super unless args.empty?
      return @values[name] if @values.key?(name)
      return nil if FIELD_NAME.match?(name)

      super
    end

    private

    def unwrap(value)
      case value
      when PayriffObject then value.to_h
      when Array then value.map { |v| unwrap(v) }
      else value
      end
    end
  end
end