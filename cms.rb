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

def create_document(name, content = '')
  File.open(File.join(data_path, name), 'w') do |file|
    file.write(content)
  end
end

before do
  headers['Content-Type'] = 'text/html;charset=utf-8'
  session[:auth] = [{username: 'admin', password: 'secret'}]
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

get '/users/signin' do
  erb :signin
end

post '/users/signin' do
  username = params[:username]
  password = params[:password]

  session[:auth].each do |hash|
    next unless hash[:username] == username
    session[:username] = username if hash[:password] == password
    break
  end

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