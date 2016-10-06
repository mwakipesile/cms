require 'yaml'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'

configure do
  enable :sessions
  set :session_secret, 'password1'
  set :erb, escape_html: true
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def credentials_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
end

def load_user_credentials
  YAML.load_file(credentials_path)
end

def create_document(name, content = '')
  File.open(File.join(data_path, name), 'w') do |file|
    file.write(content)
  end
end

before do
  headers['Content-Type'] = 'text/html;charset=utf-8'
  @users = load_user_credentials
  # session[:auth] = [{username: 'admin', password: 'secret'}]
end

helpers do
  def file_list
    Dir.glob(File.join(data_path, '*')).map { |path| File.basename(path) }
  end

  def render_markdown(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(text)
  end

  def load_file_content(path)
    content = File.read(path)
    case File.extname(path)
    when '.txt'
      headers['Content-Type'] = 'text/plain'
      content
    when '.md'
      @content = render_markdown(content)
      erb :file
    end
  end

  def invalid_username(username)  
    if username.size < 2
      session[:message] = 'Username must be at least 2 characters long'
    elsif username.match(/\W/)
      session[:message] = 'Username can contain alphanumeric only'
    elsif @users[username]
      session[:message] = 'That username has already been taken'
    end
  end

  def invalid_password(password)
    if password.size < 4
      session[:message] = 'Password must be at least 4 characters long'
    elsif password.match(/\W+/)
      session[:message] = 'Password must be alphanumeric'
    end
  end

  def restricted_message
    session[:message] = 'You must be signed in to do that'
  end

  def redirect_unauthorized_user
    return if session[:username]
    restricted_message
    redirect('/')
  end
end

get '/' do
  @filenames = file_list

  erb :index
end

get '/:filename/edit' do |filename|
  redirect_unauthorized_user

  @filename = filename
  @file_content = File.read(File.join(data_path, filename))
  headers['Content-Type'] = 'text/html;charset=utf-8'

  erb :edit_file
end

get '/new' do
  redirect_unauthorized_user
  erb :new_file
end

post '/files/create' do
  redirect_unauthorized_user

  filename = params[:document_name]

  if !filename.match(/\w+\.\w{2,}/)
    session[:message] = 'A valid name is required'
  elsif file_list.include?(filename)
    session[:message] = "A document with name #{filename} already exists"
  else
    create_document(filename)
    session[:message] = "#{filename} was created"
    redirect('/')
  end

  status(422)
  erb :new_file
end

post '/files/delete/:filename' do |filename|
  redirect_unauthorized_user

  if !file_list.include?(filename)
    session[:message] = "File with name #{filename} doesn't exist"
  else
    File.delete(File.join(data_path, filename))
    session[:message] = "#{filename} has been deleted"
  end

  redirect('/')
end

get '/users/signup' do
  erb :signup
end

post '/users/signup' do
  username = params[:username]
  password = params[:password]
  password2 = params[:password2]

  if invalid_username(username) || invalid_password(password)
    redirect('/users/signup')
  end

  if password != password2
    session[:message] = 'Passwords don\'t match'
    redirect('/users/signup')
  end

  @users[username] = { 'password' => password }
  File.open(credentials_path, 'w') do |file|
    file.write(@users.to_yaml) # or file.puts(YAML.dump(@users))
  end
  session[:message] = 'Welcome!'
  redirect('/')
end

get '/users/signin' do
  erb :signin
end

post '/users/signin' do
  username = params[:username]
  password = params[:password]

  user =   @users[username]
  session[:username] = username if user && user['password'] == password

  if session[:username]
    session[:message] = 'Welcome!'
    redirect('/')
  else
    session[:message] = 'Wrong credentials'
    erb :signin
  end
end

post '/users/signout' do
  session[:message] = "Goodbye #{session.delete(:username)}"
  redirect('/')
end

get '/*.*' do |filename, ext|
  filepath = "#{data_path}/#{filename}.#{ext}"

  if File.exist?(filepath)
    load_file_content(filepath)
  else
    session[:message] = "#{filename}.#{ext} does not exist."
    redirect('/')
  end
end

post '/:filename' do |filename|
  redirect_unauthorized_user

  filepath = File.join(data_path, filename)
  text = params[:file_content]

  File.open(filepath, 'w') { |file| file.write(text) }

  session[:message] = "#{filename} has been updated!"
  redirect('/')
end