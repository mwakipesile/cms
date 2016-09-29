ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../cms"

class CmsTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_index
    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "doc_list.txt"
    assert_includes last_response.body, "ruby_releases.txt"
  end

  def test_render_file
    get "/doc_list.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_equal "about.txt\nchanges.txt\nhistory.txt", last_response.body
  end

  def test_nonexistent_file
    get "/nonexistent.txt"
    assert_equal 302, last_response.status
    
    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "nonexistent.txt does not exist"
    assert_includes last_response.body, "doc_list.txt"
    assert_includes last_response.body, "ruby_releases.txt"
  end
end