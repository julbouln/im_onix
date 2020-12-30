require 'pp'

module ONIX
  class BuilderInvalidArgument < StandardError
  end

  class BuilderInvalidCardinality < StandardError
  end

  class BuilderInvalidCode < StandardError
  end

  class BuilderInvalidCodeAlias < StandardError
  end

  class BuilderInvalidChildElement < StandardError
  end

  # ONIX builder DSL with human code resolve, code validity and child element validity
  # WIP elements cardinality check
  class Builder
    attr_accessor :parent, :name, :element, :children

    def initialize(parent = nil)
      @children = []
      @parent = parent
    end

    def method_missing(m, *args, &block)
      @children << make_element(m, args, &block)
    end

    def to_xml(xml)
      ONIX::Serializer::Default::Subset.serialize(xml, @name, @element)
    end

    def check_cardinality!
      if @parent
        children_h = {}
        @children.compact.each do |tag|
          children_h[tag] ||= 0
          children_h[tag] += 1
        end
        @parent.class.ancestors_registered_elements.each do |k, v|
          children_h[k] ||= 0 if k.downcase != k
          if children_h[k]
            cardinality = v.cardinality
            if cardinality
              if cardinality.is_a?(Range)
                unless cardinality.cover?(children_h[k])
                  raise BuilderInvalidCardinality, [@name.to_s, k, children_h[k], cardinality]
                end
              else
                unless children_h[k] == cardinality
                  raise BuilderInvalidCardinality, [@name.to_s, k, children_h[k], cardinality]
                end
              end
            end
          end
        end
      end
    end

    private

    def make_element(nm, args, &block)
      @name = nm
      if ONIX.const_defined?(nm)
        klass = ONIX.const_get(nm)
        if klass.respond_to?(:from_code)
          if args.first.is_a?(String)
            el = klass.from_code(args.first)
            unless el.human
              raise BuilderInvalidCode, [nm.to_s, args.first]
            end
          else
            if args.first.is_a?(Symbol)
              el = klass.from_human(args.first.to_s)
              unless el.code
                raise BuilderInvalidCodeAlias, [nm.to_s, args.first.to_s]
              end
            else
              raise BuilderInvalidArgument, [nm.to_s, args.first]
            end
          end
        else
          el = klass.new
        end
      end

      if @parent
        parser_el = @parent.class.ancestors_registered_elements[nm.to_s]
        if parser_el
          if parser_el.is_array?
            arr = @parent.send(parser_el.underscore_name)
            arr << el
          else
            case parser_el.type
            when :subset
              @parent.send(parser_el.underscore_name + "=", el)
            else
              @parent.send(parser_el.underscore_name + "=", args.first)
            end
          end
        else
          raise BuilderInvalidChildElement, [@parent.class.to_s.sub("ONIX::", ""), nm.to_s]
        end
      end

      if block_given?
        builder = Builder.new(el)
        if block.arity == 1
          block.call builder
        else
          builder.instance_eval(&block)
        end
        builder.check_cardinality!
      end

      @element = el
      @name.to_s
    end
  end
end