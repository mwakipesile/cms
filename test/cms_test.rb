ENV["RACK_ENV"] = "test"
require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

class CmsTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def test_index
    get "/"
    create_document "about.md"
    create_document "ruby_releases.txt"
    create_document "doc_list.txt"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "ruby_releases.txt"
    assert_includes last_response.body, "doc_list.txt" 
  end

  def test_render_file
    create_document "test.txt", "testing this bitch!"
    get "/test.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "testing this bitch!"
  end

  def test_nonexistent_file
    get "/nonexistent.txt"
    create_document "doc_list.txt"
    create_document "ruby_releases.txt"
    create_document "about.md"
    assert_equal 302, last_response.status
    
    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "nonexistent.txt does not exist"
    assert_includes last_response.body, "doc_list.txt"
    assert_includes last_response.body, "ruby_releases.txt"
    assert_includes last_response.body, "about.md"
  end

  def test_markdown_formatting
    create_document "about.md", "# Heading\n## Sub-heading\nline  \nbreak"
    get "/about.md"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]

    [
      "<h1>Heading</h1>", "<br>", "<h2>Sub-heading</h2>"
    ].each do |line|
      assert_includes last_response.body, line
    end
  end

  def test_editing_file
    create_document "about.md"
    get '/about.md/edit'
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "form"
    assert_includes last_response.body, "fieldset"
    assert_includes last_response.body, "input"
    assert_includes last_response.body, "textarea"
  end

  def test_save_edited_file
    create_document "about.md", "photos.jpg"
    get '/about.md'
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "photos.jpg"

    post '/about.md', file_content: "# BIGHEAD\n## Small head\nline  \nbreak"
    assert_equal 302, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "about.md has been updated!"
    assert_includes last_response.body, "class="
    assert_includes last_response.body, "flash"

    get '/about.md'
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    refute_includes last_response.body, "photos.jpg"

    [
      "<h1>BIGHEAD</h1>", "<br>", "<h2>Small head</h2>"
    ].each do |line|
      assert_includes last_response.body, line
    end
  end

  def test_create_new_file
    get '/'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "New Document"
    assert_includes last_response.body, "/new"

    get '/new'
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "form"
    assert_includes last_response.body, "fieldset"
    assert_includes last_response.body, "input"
    assert_includes last_response.body, "<label for='document_name'>Add new document:</label>"
  end

  def test_save_new_file
    post '/files/create', document_name: "README.md"
    assert_equal 302, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "README.md was created"

    get '/README.md'
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]

    get "/"
    assert_includes last_response.body, "README.md"
  end

  def test_reject_blank_filename
    post '/files/create', document_name: ""
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'A valid name is required'
    assert_includes last_response.body, "form"
    assert_includes last_response.body, "fieldset"
    assert_includes last_response.body, "input"
    assert_includes last_response.body, "<label for='document_name'>Add new document:</label>"
  end

  def test_reject_filename_missing_extension
    post '/files/create', document_name: "mydoc"
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'A valid name is required'
    assert_includes last_response.body, "form"
    assert_includes last_response.body, "fieldset"
    assert_includes last_response.body, "input"
    assert_includes last_response.body, "<label for='document_name'>Add new document:</label>"
  end

  def test_reject_duplicate_filename
    post '/files/create', document_name: "mydoc.txt"

    get "/"
    assert_includes last_response.body, "mydoc.txt"

    post '/files/create', document_name: "mydoc.txt"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "mydoc.txt already exists"
    assert_includes last_response.body, "form"
    assert_includes last_response.body, "fieldset"
    assert_includes last_response.body, "input"
    assert_includes last_response.body, "<label for='document_name'>Add new document:</label>"
  end
end