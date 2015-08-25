##
# The Gin::Router class is the core of how Gin maps HTTP requests to
# a Controller and action (target), and vice-versa.
#
#   router = Gin::Router.new
#   router.add FooController do
#     get :index, "/"
#     get :show, "/:id"
#   end
#
#   router.path_to FooController, :show, id: 123
#   #=> "/foo/123"
#
#   router.path_to :show_foo, id: 123
#   #=> "/foo/123"
#
#   router.resources_for "get", "/foo/123"
#   #=> [FooController, :show, {:id => "123"}]

module Gin
  class Router
    # Raised when a Route fails to build a path due to missing params
    # or an invalid route target.
    class PathArgumentError < Gin::Error; end

    ##
    # Class for building temporary groups of routes for a given controller.
    # Used by the Gin::App.mount DSL.

    class Mount
      PATH_NAME_MATCHER = %r{\A[-+\w/]+\Z}m #:nodoc:

      VERBS = %w(get post put delete head options trace)

      VERBS.each do |verb|
        define_method(verb) { |action, *args| add(verb, action, *args) }
      end

      def initialize(ctrl, base_path = nil, &block)
        unless ctrl.respond_to?(:call)
          fail ArgumentError, "#{ctrl.inspect} must respond to `call'"
        end

        base_path ||= ctrl.controller_name if ctrl.is_a? Gin::Mountable

        unless base_path
          uname = Gin.underscore(ctrl.to_s)
          base_path = File.join('', uname) if uname =~ PATH_NAME_MATCHER
        end

        unless base_path
          fail ArgumentError, "Could not deduce base path from #{ctrl.inspect}"
        end

        @ctrl      = ctrl
        @routes    = []
        @actions   = []
        @base_path = base_path

        if block_given?
          instance_eval(&block)
          return
        end

        if @ctrl.is_a? Gin::Mountable
          defaults
        else
          any :call, '/'
        end
      end

      ##
      # Create and add default restful routes if they aren't taken already.

      def defaults
        unless @ctrl.is_a? Gin::Mountable
          fail TypeError,
            "#{@ctrl.inspect} must inherit Gin::Mountable to support defaults"
        end

        (@ctrl.actions - @actions).each do |action|
          verb, path = @ctrl.default_route_for(action)

          add(verb, action, path) unless
            @routes.any? { |route| route === [verb, path] }
        end
      end

      ##
      # Create routes for all standard verbs and add them to the Mount instance.

      def any(action, path = nil)
        VERBS.each { |verb| send verb, action, path }
      end

      ##
      # Create a single route and add it to the Mount instance.

      def add(verb, action, *args)
        path = args.shift        if args[0].is_a? String
        name = args.shift.to_sym if args[0]

        if @ctrl.is_a? Gin::Mountable
          path ||= @ctrl.default_route_for(action)[1]
          name ||= @ctrl.route_name_for(action)
        elsif !(path && name) && !action.is_a?(Array) && !action.is_a?(Hash) &&
        action.to_s =~ PATH_NAME_MATCHER
          path ||= action.to_s
          uname = Gin.underscore(@ctrl.to_s).sub(%r{^.*/}, '')
          name = "#{action}_#{uname}" if !name && uname =~ PATH_NAME_MATCHER
        end

        unless path
            fail ArgumentError, 'No path could be determined for target '\
                                "#{@ctrl.inspect} #{action.inspect}"
        end

        path = File.join(@base_path, path)
        target = [@ctrl, action]

        route = Route.new(verb, path, target, name)
        @routes << route
        @actions << action
      end

      ##
      # Iterate through through all the routes in the Mount.

      def each_route(&block)
        @routes.each(&block)
      end
    end

    ##
    # Represents an HTTP path and path matcher, with inline params, and new path
    # generation functionality.
    #
    #   r = Route.new "get", "/foo/:id.:format", [FooController, :show], :show_foo
    #   r.to_path id: 123, format: "json"
    #   #=> "/foo/123.json"

    class Route
      include Gin::Constants

      # Parsed out path param key names.
      attr_reader :param_keys

      # Array of path parts for tree-based matching.
      attr_reader :match_keys

      # Computed path String with wildcards.
      attr_reader :path

      # Target of the route, in this case an Array with controller and action.
      attr_reader :target

      # Arbitrary name of the route.
      attr_reader :name

      # HTTP verb used by the route.
      attr_reader :verb

      SEP = '/'               # :nodoc:
      VAR_MATCHER = /:(\w+)/  # :nodoc:
      PARAM_MATCHER = '(.*?)' # :nodoc:

      def initialize(verb, path, target = [], name = nil)
        @target = target
        @name   = name.to_sym if name
        build verb, path
      end

      ##
      # Render a route path by giving it inline (and other) params.
      #   route.to_path :id => 123, :format => "json", :foo => "bar"
      #   #=> "/foo/123.json?foo=bar"

      def to_path(params = {})
        params ||= {}
        rendered_path = @path.dup
        rendered_path = rendered_path % @param_keys.map do |k|
          val = params.delete(k) || params.delete(k.to_sym)
          fail PathArgumentError, "Missing param #{k}" unless val
          CGI.escape(val.to_s)
        end unless @param_keys.empty?

        rendered_path << "?#{Gin.build_query(params)}" unless params.empty?
        rendered_path
      end

      ##
      # Creates a Rack env hash with the given params and headers.

      def to_env(params = {}, headers = {})
        headers ||= {}
        params ||= {}

        path_info, query_string = to_path(params).split('?', 2)

        env = headers.merge(
          PATH_INFO => path_info,
          REQ_METHOD => @verb,
          QUERY_STRING => query_string
        )

        # TODO: implement multipart streams for requests that support a body
        env[RACK_INPUT] ||= ''
        env
      end

      ##
      # Returns true if the argument matches the route_id.
      # The route id is an array with verb and original path.

      def ===(other)
        @route_id == other
      end

      private

      def build(verb, path)
        @verb = verb.to_s.upcase

        @path = ''
        @param_keys = []
        @match_keys = []
        @route_id = [@verb, path]

        parts = [@verb].concat path.split(SEP)

        parts.each_with_index do |p, i|
          next if p.empty?

          is_param = false
          part = Regexp.escape(p).gsub!(VAR_MATCHER) do
            @param_keys << Regexp.last_match(1)
            is_param = true
            PARAM_MATCHER
          end

          if part == PARAM_MATCHER
            part = '%s'
          elsif is_param
            part = /^#{part}$/
          else
            part = p
          end

          @path << "#{SEP}#{p.gsub(VAR_MATCHER, '%s')}" if i > 0
          @match_keys << part
        end
      end
    end

    class Node # :nodoc:
      attr_accessor :value

      def initialize
        @children = {}
      end

      def [](key)
        @children[key]
      end

      def match(key)
        @children.keys.each do |k|
          next unless k.is_a? Regexp
          m = k.match key
          return [@children[k], m[1..-1]] if m
        end
        nil
      end

      def add_child(key)
        @children[key] ||= Node.new
      end
    end

    def initialize
      @routes_tree = Node.new
      @routes_lookup = {}
    end

    ##
    # Add a Controller to the router with a base path.
    # Used by Gin::App.mount.

    def add(ctrl, base_path = nil, &block)
      mount = Mount.new(ctrl, base_path, &block)

      mount.each_route do |route|
        curr_node = @routes_tree

        route.match_keys.each do |part|
          curr_node.add_child part
          curr_node = curr_node[part]
        end

        curr_node.value = route
        @routes_lookup[route.name]   = route if route.name
        @routes_lookup[route.target] = route
      end
    end

    ##
    # Check if a Controller and action pair has a route.

    def route?(ctrl, action)
      !@routes_lookup[[ctrl, action]].nil?
    end

    ##
    # Yield every route, controller, action combinations the router knows about.

    def each_route(&block)
      @routes_lookup.each do |key, route|
        next unless key.is_a? Array
        block.call route, key[0], key[1]
      end
    end

    ##
    # Get the path to the given Controller and action combo or route name,
    # provided with the needed params. Routes with missing path params will raise
    # MissingParamError. Missing routes will raise a RouterError.
    # Returns a String starting with "/".
    #
    #   path_to FooController, :show, id: 123
    #   #=> "/foo/123"
    #
    #   path_to :show_foo, id: 123
    #   #=> "/foo/123"
    #
    #   path_to :show_foo, id: 123, more: true
    #   #=> "/foo/123?more=true"

    def path_to(*args)
      params = args.pop.dup if args.last.is_a? Hash
      route = route_to(*args)
      route.to_path(params)
    end

    ##
    # Get the route object to the given Controller and action combo or route name.
    # MissingParamError. Returns a Gin::Router::Route instance.
    # Raises a RouterError if no route can be found.
    #
    #   route_to FooController, :show
    #   route_to :show_foo

    def route_to(*args)
      key = args[0].is_a? Class ? args.slice!(0..1) : args.shift
      route = @routes_lookup[key]

      unless route
        if key.is_a?(Array) && key[0].is_a?(Gin::Mountable)
          name = key[0].display_name(key[1])
        else
          name = name.inspect
        end

        fail Gin::RouterError, "No route for #{name}"
      end

      route
    end

    ##
    # Takes a path and returns an array with the
    # controller class, action symbol, processed path params.
    #
    #   router.resources_for "get", "/foo/123"
    #   #=> [FooController, :show, {:id => "123"}]
    #
    # Returns nil if no match was found.

    def resources_for(http_verb, path)
      param_vals = []
      curr_node  = @routes_tree[http_verb.to_s.upcase]
      return unless curr_node

      path.scan(%r{/([^/]+|$)}) do |matches|
        key = matches[0]
        next if key.empty?

        if curr_node[key]
          curr_node = curr_node[key]

        elsif curr_node['%s']
          param_vals << CGI.unescape(key)
          curr_node = curr_node['%s']

        elsif child_and_matches = curr_node.match(CGI.unescape(key))
          param_vals.concat child_and_matches[1]
          curr_node = child_and_matches[0]

        else
          break
        end
      end

      return unless curr_node.value
      route = curr_node.value

      if param_vals.empty?
        path_params = {}
      else
        path_params = route.param_keys.each_with_object({}) do |name, h|
          h[name] = param_vals.shift
        end
      end

      [route.target, path_params]
    end
  end
end