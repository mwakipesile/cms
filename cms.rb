require 'yaml'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'
require 'bcrypt'

include FileUtils

RESTRICTED = %w(new create delete duplicate edit signout upload)
VALID_FILE_EXTENSIONS = %w(.bmp .txt .md .doc .gif .jpg .jpeg .png .pdf).freeze
IMG_EXTNAMES = %w(.jpg .jpeg .png .gif .bmp).freeze

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

def full_path(path)
  if ENV['RACK_ENV'] == 'test'
    return File.expand_path("../test/#{path}", __FILE__)
  else
    File.expand_path("../#{path}", __FILE__)
  end
end

def data_path
  full_path('data')
end

def image_path
  full_path('public/uploads/')
end

def credentials_path
  full_path('users.yml')
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

  pass unless restricted_route?
  redirect_unauthorized_user
end

helpers do
  def file_list(directory = nil)
    abs_path = directory.nil? ? data_path : File.join(data_path, directory)
    Dir.glob(File.join(abs_path, '*.*')).map { |path| File.basename(path) }
  end

  def flash_message(message, key = :message)
    session[key] ||= message
  end

  def redirect_unless_file_exists(filename, path = nil)
    path ||= data_path
    return if File.exist?(File.join(path, filename))
    flash_message("#{filename} does not exist.")
    redirect('/')
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
      flash_message('Username must be at least 2 characters long')
    elsif username =~ /\W/
      flash_message('Username can contain alphanumeric only')
    elsif @users[username]
      flash_message('That username has already been taken')
    end
  end

  def invalid_password(password)
    if password.size < 4
      flash_message('Password must be at least 4 characters long')
    elsif !password.match(/\w+/)
      flash_message('Password must contain alphanumeric character')
    end
  end

  def restricted_route?
    RESTRICTED.include?(request.path_info.split('/')[2])
  end

  def redirect_unauthorized_user
    return if session[:username]
    session[:message] ||= 'You must be signed in to do that'
    redirect(request.referrer)
  end

  def redirect_logged_in_user
    return unless session[:username]
    flash_message('You are already logged in')
    redirect(request.referrer)
  end

  def create_duplicate_file_name(filename)
    current_files = file_list
    basename = File.basename(filename, filename.match(/\d*\.\w{2,}/).to_s)
    copy_number = filename.match(/\d+(?!.*\d+)/).to_s.to_i + 1

    loop do
      new_filename = "#{basename}#{copy_number}#{File.extname(filename)}"
      return new_filename unless current_files.include?(new_filename)
      copy_number += 1
    end
  end

  def revisions_dir(filename)
    filename.reverse.sub('.', '').reverse
  end

  def save_old_content(filename)
    filepath = File.join(data_path, filename)
    file_ext = File.extname(filename)
    old_content = File.read(filepath)

    dir = revisions_dir(filename)
    revisions_path = File.join(data_path, dir)
    Dir.mkdir revisions_path unless File.directory?(revisions_path)

    revisions = file_list(dir)
    revision_name = create_revision_name(revisions, file_ext)

    create_document("#{dir}/#{revision_name}", old_content)
  end

  def create_revision_name(revisions, extname)
    return "1#{extname}" if revisions.empty?

    last_revision = revisions.map { |rev| File.basename(rev, '.*').to_i }.max
    "#{last_revision + 1}#{extname}"
  end
end

get '/' do
  @filenames = file_list

  erb :index
end

get '/files/new' do
  erb :new_file
end

post '/files/create' do
  filename = params[:document_name]

  if !filename.match(/\w+\.\w{2,}/)
    flash_message('A valid file name is required')
  elsif !VALID_FILE_EXTENSIONS.include?(File.extname(filename))
    flash_message(
      "Unsupported extension. File must be one of the following types: \n" \
      "(#{VALID_FILE_EXTENSIONS.join(', ')})"
    )
  elsif file_list.include?(filename)
    flash_message("A document with name #{filename} already exists")
  else
    create_document(filename)
    flash_message("#{filename} was created")
    redirect('/')
  end

  status(422)
  erb :new_file
end

get '/:filename/edit' do |filename|
  redirect_unless_file_exists(filename)

  @filename = filename
  @file_content = File.read(File.join(data_path, filename))
  headers['Content-Type'] = 'text/html;charset=utf-8'

  erb :edit_file
end

post '/:filename/edit' do |filename|
  redirect_unless_file_exists(filename)
  save_old_content(filename)

  edited_content = params[:file_content]
  filepath = File.join(data_path, filename)
  File.open(filepath, 'w') { |file| file.write(edited_content) }

  flash_message("#{filename} has been updated!")
  redirect('/')
end

get '/:filename/revisions' do |filename|
  redirect_unless_file_exists(filename)

  dir = revisions_dir(filename)
  @filename = filename
  @revisions = file_list(dir).map { |file| File.basename(file, '.*') }

  erb :revisions
end

get '/:filename/revisions/:number' do |filename, number|
  redirect_unless_file_exists(filename)

  revision_name = "#{number}#{File.extname(filename)}"
  dir = revisions_dir(filename)

  load_file_content(File.join(data_path, "#{dir}/#{revision_name}"))
end

post '/files/delete/:filename' do |filename|
  redirect_unless_file_exists(filename)

  File.delete(File.join(data_path, filename))

  revisions = File.join(data_path, filename.sub('.', ''))
  FileUtils.rm_rf(revisions, secure: true) if File.directory?(revisions)

  flash_message("#{filename} has been deleted")

  if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
    session.delete(:message)
    status 204
  else
    redirect('/')
  end
end

post '/files/duplicate/:filename' do |filename|
  redirect_unless_file_exists(filename)

  new_filename = create_duplicate_file_name(filename)
  source_path = File.join(data_path, filename)
  destination_path = File.join(data_path, new_filename)
  FileUtils.cp(source_path, destination_path)

  flash_message("#{new_filename} has been created")

  redirect('/')
end

get '/users/signup' do
  redirect_logged_in_user
  erb :signup
end

post '/users/signup' do
  redirect_logged_in_user

  username = params[:username]
  password = params[:password]
  password2 = params[:password2]

  if invalid_username(username) || invalid_password(password)
  elsif password != password2
    flash_message('Passwords don\'t match')
  else
    @users[username] = { 'password' => encrypt(password) }
    File.open(credentials_path, 'w') do |file|
      file.write(@users.to_yaml) # or file.puts(YAML.dump(@users))
    end

    session[:username] = username
    flash_message('Welcome!')
    redirect('/')
  end

  erb :signup
end

get '/users/signin' do
  redirect_logged_in_user
  erb :signin
end

post '/users/signin' do
  redirect_logged_in_user
  username = params[:username]
  password = params[:password]

  user =   @users[username]
  session[:username] = username if user && check?(password, user['password'])

  if session[:username]
    flash_message('Welcome!')
    redirect('/')
  else
    status(422)
    flash_message('Invalid credentials')
    erb :signin
  end
end

post '/users/signout' do
  flash_message("Goodbye #{session.delete(:username)}")
  redirect(request.referrer)
end

get %r{/(.+\.(?!.*\.)\w{2,})} do |filename|
  ext = File.extname(filename)
  filepath = IMG_EXTNAMES.include?(ext) ? 'public/uploads' : data_path 

  redirect_unless_file_exists(filename, filepath)
  load_file_content(File.join(filepath, filename))
end

get '/files/upload' do
  erb :upload
end

post '/files/upload' do
  params[:files].each do |file|
    filename = params[file[:filename]] || file[:filename]
    tmpfile = file[:tempfile]

    FileUtils.cp(tmpfile.path, File.join(image_path, filename))
  end

  redirect('/')
end
