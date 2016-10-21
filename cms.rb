require 'yaml'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'
require 'bcrypt'

include FileUtils

VALID_FILE_EXTENSIONS = %w(.txt .md .doc .jpg .jpeg .png .pdf)
IMG_EXTNAMES = %w(jpg jpeg png gif bmp)

configure do
  enable :sessions
  set :session_secret, 'password1'
  set :erb, escape_html: true
end

def encrypt(password)
  BCrypt::Password.create(password)
end

def check?(password, encrypted_password)
  BCrypt::Password.new(encrypted_password) == password
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def image_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path("../test/uploads", __FILE__)
  else
    "public/uploads/"
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
end

helpers do
  def file_list(directory = nil)
    abs_path = directory.nil? ? data_path : File.join(data_path, directory)
    Dir.glob(File.join(abs_path, '*.*')).map { |path| File.basename(path) }
  end

  def render_markdown(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(text)
  end

  def load_file_content(path)
    case File.extname(path)
    when '.txt'
      headers['Content-Type'] = 'text/plain'
      send_file path
    when '.md'
      @content = render_markdown(File.read(path))
      erb :file
    else
      send_file open(path), type: 'image/png'
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
    elsif !password.match(/\w+/)
      session[:message] = 'Password must contain alphanumeric character'
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

  def create_duplicate_file_name(filename)
    current_files = file_list
    basename = File.basename(filename, filename.match(/\d*\.\w{2,}/).to_s)
    append_number = filename.match(/\d+(?!.*\d+)/).to_s.to_i + 1

    loop do
      new_filename = "#{basename}#{append_number}#{File.extname(filename)}"
      return new_filename unless current_files.include?(new_filename)
      append_number += 1
    end
  end

  def save_old_content(filename)
    filepath = File.join(data_path, filename)
    file_ext = File.extname(filename)
    old_content = File.read(filepath)
    
    revisions_dir = filename.sub('.', '')
    revisions_path = File.join(data_path, revisions_dir)
    Dir.mkdir revisions_path unless File.directory?(revisions_path)

    revisions = file_list(revisions_dir)

    if revisions.empty?
      revision_name = "1#{file_ext}"
    else
      basename = revisions.map { |rev| File.basename(rev, '.*').to_i }.max
      revision_name = "#{basename + 1}#{file_ext}"
    end
    
    create_document("#{revisions_dir}/#{revision_name}", old_content )
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
  elsif !VALID_FILE_EXTENSIONS.include?(File.extname(filename))
    session[:message] = 'Invalid extension'
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
    
    revisions = File.join(data_path, filename.sub('.', ''))
    FileUtils.rm_rf(revisions, secure: true) if File.directory?(revisions)

    session[:message] = "#{filename} has been deleted"
  end

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    session.delete(:message)
    status 204
  else
    redirect('/')
  end
end

post '/files/duplicate/:filename' do |filename|
  redirect_unauthorized_user

  if !file_list.include?(filename)
    session[:message] = "File with name #{filename} doesn't exist"
  else
    new_filename = create_duplicate_file_name(filename)
    source_path = File.join(data_path, filename)
    destination_path = File.join(data_path, new_filename)
    FileUtils.cp(source_path, destination_path)

    session[:message] = "#{new_filename} has been created"
  end

  redirect('/')
end

get '/:filename/revisions' do |filename|

  if !file_list.include?(filename)
    session[:message] = "File with name #{filename} doesn't exist"
    redirect('/')
  end

  revisions_dir = filename.sub('.', '')

  @revisions = file_list(revisions_dir).map { |file| File.basename(file, '.*')}
  @filename = filename

  erb :revisions
end

post '/:filename/edit' do |filename|
  redirect_unauthorized_user

  filepath = File.join(data_path, filename)

  save_old_content(filename)
  edited_content = params[:file_content]

  File.open(filepath, 'w') { |file| file.write(edited_content) }

  session[:message] = "#{filename} has been updated!"
  redirect('/')
end

get '/:filename/revisions/:number' do |filename, number|

  if !file_list.include?(filename)
    session[:message] = "File with name #{filename} doesn't exist"
    redirect('/')
  end

  revision_name = "#{number}#{File.extname(filename)}"
  revisions_dir = filename.sub('.', '')

  load_file_content(File.join(data_path, "#{revisions_dir}/#{revision_name}"))
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

  @users[username] = { 'password' => encrypt(password) }
  File.open(credentials_path, 'w') do |file|
    file.write(@users.to_yaml) # or file.puts(YAML.dump(@users))
  end

  session[:username] = username
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
  session[:username] = username if user && check?(password, user['password'])

  if session[:username]
    session[:message] = 'Welcome!'
    redirect('/')
  else
    status(422)
    session[:message] = 'Invalid credentials'
    erb :signin
  end
end

post '/users/signout' do
  session[:message] = "Goodbye #{session.delete(:username)}"
  redirect('/')
end

get '/*.*' do |filename, ext|
  if IMG_EXTNAMES.include?(ext)
    filepath = "public/uploads/#{filename}.#{ext}"
  else
    filepath = "#{data_path}/#{filename}.#{ext}"
  end

  if File.exist?(filepath)
    load_file_content(filepath)    
  else
    session[:message] = "#{filename}.#{ext} does not exist."
    redirect('/')
  end
end

get '/files/upload' do
  redirect_unauthorized_user
  erb :upload
end

post '/files/upload' do
  redirect_unauthorized_user

  files = params[:files]

  files.each do |file|
    filename = file[:filename]
    tmpfile = file[:tempfile]

    FileUtils.cp(tmpfile.path, File.join(image_path, filename))
  end

  redirect('/')
end
