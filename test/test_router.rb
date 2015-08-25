require "test/test_helper"

class MyCtrl < Gin::Controller;
  def index; end
  def show; end
  def unmounted_action; end
end

class FooController < Gin::Controller; end


class RouterTest < Test::Unit::TestCase

  def setup
    @router = Gin::Router.new
  end


  def test_add_and_retrieve
    @router.add MyCtrl, '/my_ctrl' do
      get  :bar, "/bar"
      post :foo
      any  :thing
    end

    assert_equal [[MyCtrl, :bar], {}],
      @router.resources_for("GET", "/my_ctrl/bar")

    assert_equal [[MyCtrl, :foo], {}],
      @router.resources_for("post", "/my_ctrl/foo")

    assert_nil @router.resources_for("post", "/my_ctrl")

    %w{get post put delete head options trace}.each do |verb|
      assert_equal [[MyCtrl, :thing], {}],
        @router.resources_for(verb, "/my_ctrl/thing")
    end
  end


  def test_add_and_retrieve_cgi_escaped
    @router.add MyCtrl, '/my_ctrl' do
      get  :bar, "/bar/:id"
    end

    assert_equal [[MyCtrl, :bar], {'id' => '123 456'}],
      @router.resources_for("GET", "/my_ctrl/bar/123+456")
  end


  def test_add_and_retrieve_complex_cgi_escaped
    @router.add MyCtrl, '/my_ctrl' do
      get  :bar, "/bar/:type/:id.:format"
    end

    assert_equal [[MyCtrl, :bar], {"type"=>"[I]", "id"=>"123 456", "format"=>"json"}],
      @router.resources_for("GET", "/my_ctrl/bar/%5BI%5D/123+456.json")
  end


  def test_add_and_retrieve_named_route
    @router.add FooController, "/foo" do
      get  :index, "/", :all_foo
      get  :bar, :my_bar
      post :create
    end

    assert_equal [[FooController, :bar], {}],
      @router.resources_for("GET", "/foo/bar")

    assert_equal "/foo/bar", @router.path_to(:my_bar)
    assert_equal "/foo", @router.path_to(:create_foo)
    assert_equal "/foo", @router.path_to(:all_foo)
  end


  def test_add_and_retrieve_w_path_params
    @router.add MyCtrl, '/my_ctrl/:str' do
      get  :bar, "/bar"
      post :foo, "/"
    end

    assert_nil @router.resources_for("post", "/my_ctrl")

    assert_equal [[MyCtrl, :bar], {'str' => 'item'}],
      @router.resources_for("GET", "/my_ctrl/item/bar")

    assert_equal [[MyCtrl, :foo], {'str' => 'item'}],
      @router.resources_for("post", "/my_ctrl/item")
  end


  def test_add_and_retrieve_path_matcher
    @router.add MyCtrl, "/" do
      get :bar, "/bar/:type/:id.:format"
    end

    expected_params = {'type' => 'sub', 'id' => '123', 'format' => 'json'}
    assert_equal [[MyCtrl, :bar], expected_params],
      @router.resources_for("GET", "/bar/sub/123.json")
  end


  def test_add_and_retrieve_lambda
    ctrl = lambda{ "foo" }
    @router.add ctrl, "/foo"

    assert_equal [[ctrl, :call],{}], @router.resources_for("GET", "/foo")
  end


  def test_add_and_retrieve_lambda_block
    ctrl = lambda{ "foo" }
    @router.add ctrl, "/foo" do
      get :thing, "/thing"
    end

    assert_equal [[ctrl, :thing],{}], @router.resources_for("GET", "/foo/thing")
  end


  def test_add_lambda_no_path
    ctrl = lambda{ "foo" }

    assert_raises ArgumentError do
      @router.add ctrl
    end
  end


  def test_add_lambda_defaults
    ctrl = lambda{ "foo" }

    assert_raises TypeError do
      @router.add ctrl, "/foo" do
        get :thing, "/thing"
        defaults
      end
    end
  end


  class MockCustomMount
    def self.call env
      [200, {}, ["OK"]]
    end
  end

  def test_add_and_retrieve_custom_mount
    @router.add MockCustomMount

    assert_equal [[MockCustomMount, :call],{}],
      @router.resources_for("GET", "/router_test/mock_custom_mount")

    assert_equal [MockCustomMount, :call],
      @router.route_to(MockCustomMount, :call).target

    assert_equal [MockCustomMount, :call],
      @router.route_to(:call_mock_custom_mount).target
  end


  def test_add_and_retrieve_custom_mount_block
    @router.add MockCustomMount do
      post :foo
      get [:foo, 1, 2], "/ary"
    end

    assert_equal [[MockCustomMount, :foo],{}],
      @router.resources_for("POST", "/router_test/mock_custom_mount/foo")

    assert_equal [[MockCustomMount, [:foo, 1, 2]],{}],
      @router.resources_for("GET", "/router_test/mock_custom_mount/ary")

    assert_equal [MockCustomMount, :foo],
      @router.route_to(:foo_mock_custom_mount).target

    assert_nil @router.route_to(MockCustomMount, [:foo, 1, 2]).name
  end


  def test_add_custom_mount_action
    assert_raises ArgumentError do
      @router.add MockCustomMount do
        post [:foo, 1, 2]
      end
    end
  end


  def test_add_custom_mount_defaults
    assert_raises TypeError do
      @router.add MockCustomMount, "/foo" do
        get :thing, "/thing"
        defaults
      end
    end
  end


  def test_add_and_retrieve_custom_mount_invalid
    assert_raises ArgumentError do
      @router.add TypeError
    end
  end


  def test_add_omit_base_path
    @router.add MyCtrl do
      get :bar
    end

    assert_equal [[MyCtrl, :bar], {}],
      @router.resources_for("GET", "/my_ctrl/bar")
  end


  def test_add_omit_base_path_controller
    @router.add FooController do
      get :index, '/'
    end

    assert_equal [[FooController, :index], {}],
      @router.resources_for("GET", "/foo")
  end


  def test_add_root_base_path
    @router.add MyCtrl, "/" do
      get :bar, "/"
    end

    assert_equal [[MyCtrl, :bar], {}],
      @router.resources_for("GET", "/")

    assert !@router.route?(MyCtrl, :show)
    assert !@router.route?(MyCtrl, :index)
  end


  def test_add_default_restful_routes
    @router.add MyCtrl, "/" do
      get :show, "/:id"
    end

    assert !@router.route?(MyCtrl, :index)
    assert !@router.route?(MyCtrl, :unmounted_action)
  end


  def test_add_all_routes_as_defaults
    @router.add MyCtrl, "/" do
      get :show, "/:id"
      defaults
    end

    assert @router.route?(MyCtrl, :index)
    assert @router.route?(MyCtrl, :unmounted_action)
  end


  def test_add_all
    @router.add MyCtrl, "/"

    assert_equal [[MyCtrl, :index], {}],
      @router.resources_for("GET", "/")

    assert_equal [[MyCtrl, :show], {'id' => '123'}],
      @router.resources_for("GET", "/123")

    assert_equal [[MyCtrl, :unmounted_action], {}],
      @router.resources_for("GET", "/unmounted_action")
  end


  def test_has_route
    @router.add MyCtrl, '/my_ctrl/:str' do
      get  :bar, "/bar"
      post :foo, "/"
    end

    assert @router.route?(MyCtrl, :bar)
    assert @router.route?(MyCtrl, :foo)
    assert !@router.route?(MyCtrl, :thing)
  end


  def test_path_to
    @router.add MyCtrl, '/my_ctrl/' do
      get :bar, "/bar"
    end

    assert_equal "/my_ctrl/bar", @router.path_to(MyCtrl, :bar)
  end


  def test_path_to_missing
    @router.add MyCtrl, '/my_ctrl/' do
      get :bar, "/bar"
    end

    assert_raises Gin::RouterError do
      @router.path_to(MyCtrl, :foo)
    end
  end


  def test_path_to_param
    @router.add MyCtrl, '/my_ctrl/' do
      get :show, "/:id"
    end

    assert_equal "/my_ctrl/val", @router.path_to(MyCtrl, :show, "id" => "val")

    assert_equal "/my_ctrl/val", @router.path_to(MyCtrl, :show, :id => "val")
  end


  def test_path_to_param_missing
    @router.add MyCtrl, '/my_ctrl/' do
      get :show, "/:id"
    end

    assert_raises Gin::Router::PathArgumentError do
      @router.path_to(MyCtrl, :show)
    end
  end


  def test_path_to_complex_param
    @router.add MyCtrl, "/" do
      get :bar, "/bar/:type/:id.:format"
    end

    params = {'type' => 'sub', 'id' => 123, 'format' => 'json', 'more' => 'hi'}
    assert_equal "/bar/sub/123.json?more=hi", @router.path_to(MyCtrl, :bar, params)
  end


  def test_path_to_complex_param_missing
    @router.add MyCtrl, "/" do
      get :bar, "/bar/:type/:id.:format"
    end

    params = {'type' => 'sub', 'id' => '123', 'more' => 'hi'}
    assert_raises Gin::Router::PathArgumentError do
      @router.path_to(MyCtrl, :bar, params)
    end
  end


  def test_path_to_complex_param_cgi_escaped
    @router.add MyCtrl, "/" do
      get :bar, "/bar/:type/:id.:format"
    end

    params = {'type' => 'sub/thing', 'id' => '123&4', 'more' => 'hi there', 'format' => 'json'}
    assert_equal "/bar/sub%2Fthing/123%264.json?more=hi+there",
      @router.path_to(MyCtrl, :bar, params)
  end


  def test_route_to
    @router.add MyCtrl, '/my_ctrl/' do
      get :show, "/:id"
    end

    route = @router.route_to(MyCtrl, :show)
    assert_equal [MyCtrl, :show], route.target
    assert_equal '/my_ctrl/123', route.to_path(:id => 123)

    named_route = @router.route_to(:show_my_ctrl)
    assert_equal route, named_route
  end


  def test_route_to_env
    @router.add MyCtrl, '/my_ctrl/' do
      post :update, "/:id"
    end

    route = @router.route_to(MyCtrl, :update)
    expected_env = {'rack.input' => '', 'PATH_INFO' => '/my_ctrl/123',
      'REQUEST_METHOD' => 'POST', 'QUERY_STRING' => 'blah=456'}

    assert_equal expected_env, route.to_env(:id => 123, :blah => 456)

    assert_raises Gin::Router::PathArgumentError do
      route.to_env(:blah => 456)
    end

    expected_env['rack.input'] = 'foo=bar'
    assert_equal expected_env,
      route.to_env({:id => 123, :blah => 456}, {'rack.input' => 'foo=bar'})
  end
end
