# frozen_string_literal: true

require "date"
require "time"

module Payriff
  module Util
    MAX_PAGE_SIZE = 20
    UNRESERVED = /[^A-Za-z0-9\-._~]/

    module_function

    def escape(value)
      value.to_s.b.gsub(UNRESERVED) { |c| format("%%%02X", c.ord) }
    end

    def segment(value, name)
      raise ArgumentError, "#{name} must not be blank" if !value.is_a?(String) || value.strip.empty?

      escape(value)
    end

    def required(value, name)
      raise ArgumentError, "#{name} is required" if value.nil? || (value.respond_to?(:empty?) && value.empty?)

      value
    end

    def to_amount(value, name)
      return nil if value.nil?

      Float(value.is_a?(String) ? value : value.to_s)
    rescue ArgumentError, TypeError
      raise ArgumentError, "#{name} must be a number"
    end

    def compact(hash)
      hash.reject { |_, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
    end

    def stringify(value)
      value.is_a?(Symbol) ? value.to_s.upcase : value
    end

    def date_time(value)
      case value
      when nil then nil
      when Time, DateTime then value.strftime("%Y-%m-%dT%H:%M:%S")
      when Date then value.strftime("%Y-%m-%dT00:00:00")
      else value.to_s
      end
    end

    def filter_date(value, name)
      case value
      when nil then nil
      when Date, Time then value.strftime("%d.%m.%Y")
      when /\A(\d{4})-(\d{2})-(\d{2})\z/ then "#{Regexp.last_match(3)}.#{Regexp.last_match(2)}.#{Regexp.last_match(1)}"
      else raise ArgumentError, "#{name} must be a Date, Time or YYYY-MM-DD string"
      end
    end

    def page_query(page, size)
      page ||= 0
      size ||= 10
      raise ArgumentError, "page must be >= 0" unless page.is_a?(Integer) && page >= 0
      raise ArgumentError, "size must be 1-#{MAX_PAGE_SIZE}" unless size.is_a?(Integer) && size.between?(1, MAX_PAGE_SIZE)

      [["page", page], ["offset", size]]
    end
  end
end