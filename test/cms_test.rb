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

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { 'rack.session' => { username: 'admin' } }
  end

  File.open(credentials_path, 'w') do |file|
    file.write({ 'admin' => { 'password' => encrypt('secret') }}.to_yaml)
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
    assert_equal "nonexistent.txt does not exist.", session[:message]
    
    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response.[]("Content-Type")
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

    get '/about.md/edit', {}, admin_session
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "form"
    assert_includes last_response.body, "fieldset"
    assert_includes last_response.body, "input"
    assert_includes last_response.body, "textarea"
  end

  def test_save_edited_file
    create_document "about.md", "photos.jpg"

    get '/about.md/edit', {}, admin_session
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "photos.jpg"

    post '/about.md/edit', file_content: "# BIGHEAD\n## Small head\nline  \nbreak"
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

  def test_file_revisions
    create_document "about.md", "photos.jpg"

    get '/about.md/revisions', {}, admin_session
    refute_includes last_response.body, '/about.md/revisions/1'

    post '/about.md/edit', file_content: "# BIGHEAD\n## Small head\nline"

    get '/about.md/revisions'
    assert_includes last_response.body, '/about.md/revisions/1'

    get '/about.md/revisions/1'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'photos.jpg'
  end

  def test_create_new_file
    get '/', {}, admin_session
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
    post '/files/create', { document_name: "README.md" }, admin_session
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
    post '/files/create', { document_name: ""} , admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'A valid name is required'
    assert_includes last_response.body, "form"
    assert_includes last_response.body, "fieldset"
    assert_includes last_response.body, "input"
    assert_includes last_response.body, "<label for='document_name'>Add new document:</label>"
  end

  def test_reject_filename_missing_extension
    post '/files/create', { document_name: "mydoc" }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'A valid name is required'
    assert_includes last_response.body, "form"
    assert_includes last_response.body, "fieldset"
    assert_includes last_response.body, "input"
    assert_includes last_response.body, "<label for='document_name'>Add new document:</label>"
  end

  def test_reject_duplicate_filename
    post '/files/create', { document_name: "mydoc.txt" }, admin_session

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

  def test_delete_file
    post '/files/create', { document_name: "mydoc.txt" }, admin_session
    post '/files/create', document_name: "mydoc.md"

    get "/"
    assert_includes last_response.body, "mydoc.txt"
    assert_includes last_response.body, "mydoc.md"

    post '/files/delete/mydoc.txt'
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "mydoc.txt has been deleted"

    get '/'
    refute_includes last_response.body, "mydoc.txt"
    assert_includes last_response.body, "mydoc.md"
  end

  def test_sign_up_page
    get '/users/signup'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<form action='/users/signup"
    assert_includes last_response.body, "method='post'"
    assert_includes last_response.body, "<label for='password'"
    assert_includes last_response.body, "<label for='password2'"
    assert_includes last_response.body, "<input name='username'"
    assert_includes last_response.body, "<input name='password'"
    assert_includes last_response.body, "<input name='password2'"
    assert_includes last_response.body, "<input type='submit'"
  end

  def test_successful_signup
    post '/users/signup', username: 'admin2', password: 'secret2', password2: 'secret2'
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]

    get last_response["Location"]
    assert_equal "admin2", session[:username]
    assert_equal 200, last_response.status
    refute_includes last_response.body, "<form action='/users/signin"
    assert_includes last_response.body, "Signed in as admin"
    assert_includes last_response.body, "<form action='/users/signout'"
    assert_includes last_response.body, "method='post'"
    refute_includes last_response.body, "<label for='password'"
  end

  def test_signup_with_unmatched_passwords
    post '/users/signup', username: 'admin1', password: 'secret', password2: 'secret2'
    assert_equal 302, last_response.status
    assert_equal "Passwords don't match", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<form action='/users/signup"
    assert_includes last_response.body, "method='post'"
    assert_includes last_response.body, "<label for='password'"
    assert_includes last_response.body, "<label for='password2'"
  end

  def test_sign_in_page
    get '/users/signin'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<form action='/users/signin"
    assert_includes last_response.body, "method='post'"
    assert_includes last_response.body, "<label for='password'"
    assert_includes last_response.body, "<input type='submit'"
  end

  def test_signin_with_wrong_credentials
    post '/users/signin', username: 'admin', password: 'papaya'
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Invalid credentials'
    assert_includes last_response.body, "<form action='/users/signin"
    assert_includes last_response.body, "method='post'"
    assert_includes last_response.body, "<label for='password'"
    assert_includes last_response.body, "<input type='submit'"
  end

  def test_successful_signin
    post '/users/signin', username: 'admin', password: 'secret'
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]

    get last_response["Location"]
    assert_equal "admin", session[:username]
    assert_equal 200, last_response.status
    refute_includes last_response.body, "<form action='/users/signin"
    assert_includes last_response.body, "Signed in as admin"
    assert_includes last_response.body, "<form action='/users/signout'"
    assert_includes last_response.body, "method='post'"
    refute_includes last_response.body, "<label for='password'"
  end

  def test_signout
    get '/', {}, admin_session
    assert_equal 200, last_response.status
    assert_equal 'admin', session[:username]
    refute_includes last_response.body, "<form action='/users/signin"
    assert_includes last_response.body, "Signed in as admin"

    post '/users/signout'
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_equal nil, session[:username]
    assert_includes last_response.body, "Goodbye admin"
    assert_includes last_response.body, "href='/users/signin'>Sign In"
    refute_includes last_response.body, "Signed in as admin"
    refute_includes last_response.body, "<form action='/users/signout'"
  end

  def test_restricted_actions
    create_document "about.md"
    create_document "ruby_releases.txt"
    create_document "doc_list.txt"

    get '/doc_list.txt/edit'
    assert_equal 302, last_response.status
    assert_equal  "You must be signed in to do that", session[:message]

    get last_response['location']
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "ruby_releases.txt"
    assert_includes last_response.body, "doc_list.txt"
  end

  def test_duplicate_file
    post '/files/create', { document_name: "mydoc.txt" }, admin_session

    get "/"
    assert_includes last_response.body, "mydoc.txt"
    refute_includes last_response.body, "mydoc1.txt"

    post '/files/duplicate/mydoc.txt'
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "mydoc1.txt has been created"
    assert_includes last_response.body, "mydoc.txt"
    assert_includes last_response.body, "mydoc1.txt"
  end

  def test_image_upload_form

  end
end
