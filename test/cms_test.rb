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
    assert_includes last_response.body, "about.md"
  end

  def test_render_file
    get "/doc_list.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "about"
    assert_includes last_response.body, "changes"
    assert_includes last_response.body, "history"
  end

  def test_nonexistent_file
    get "/nonexistent.txt"
    assert_equal 302, last_response.status
    
    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    #assert_includes last_response.body, "nonexistent.txt does not exist"
    assert_includes last_response.body, "doc_list.txt"
    assert_includes last_response.body, "ruby_releases.txt"
    assert_includes last_response.body, "about.md"
  end

  def test_markdown_formatting
    get "/about.md"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]

    [
      "<h1>Heading</h1>", "<h2>Sub-heading</h2>"
    ].each do |line|
      assert_includes last_response.body, line
    end
  end

  def test_editing_file
    get '/doc_list.txt/edit'
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "form"
    assert_includes last_response.body, "fieldset"
    assert_includes last_response.body, "input"
    assert_includes last_response.body, "textarea"
  end

  def test_save_edited_file
    post '/doc_list.txt', file_content: "about\nchanges\nhistory\njaribio.txt"
    assert_equal 302, last_response.status

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "jaribio.txt"
  end
end