# frozen_string_literal: true

require "active_support/notifications"
require_relative "node"

module Foundries
  module Recording
    class Collector
      def initialize
        @results = {}
        @total_creates = 0
        @subscriber = nil
        @stack = nil
        @current_root = nil
      end

      def start_test(test_id)
        @current_root = MutableNode.new(:__root__, [])
        @stack = [@current_root]

        @subscriber = ActiveSupport::Notifications.subscribe(
          "factory_bot.run_factory",
          Subscriber.new(self)
        )
      end

      def stop_test(test_id)
        ActiveSupport::Notifications.unsubscribe(@subscriber)
        @subscriber = nil

        @results[test_id] = freeze_tree(@current_root)
        @stack = nil
        @current_root = nil
      end

      attr_reader :results

      attr_reader :total_creates

      # @api private — called by the Subscriber
      def handle_start(payload)
        return unless payload[:strategy] == :create

        traits = payload[:traits] || []
        mutable = MutableNode.new(payload[:name], traits)
        @stack.last.children << mutable
        @stack.push(mutable)
      end

      # @api private — called by the Subscriber
      def handle_finish(payload)
        return unless payload[:strategy] == :create

        @stack.pop
        @total_creates += 1
      end

      private

      def freeze_tree(mutable)
        frozen_children = mutable.children.map { |child| freeze_tree(child) }
        Node.new(
          factory: mutable.factory,
          traits: mutable.traits,
          children: frozen_children
        )
      end

      MutableNode = Struct.new(:factory, :traits) do
        def children
          @children ||= []
        end
      end

      class Subscriber
        def initialize(collector)
          @collector = collector
        end

        def start(_name, _id, payload)
          @collector.handle_start(payload)
        end

        def finish(_name, _id, payload)
          @collector.handle_finish(payload)
        end
      end
    end
  end
end
