require 'yaml'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'
require 'bcrypt'

include FileUtils

RESTRICTED = %w(new create delete duplicate edit signout upload).freeze
VALID_FILE_EXTENSIONS = %w(.bmp .txt .md .doc .gif .jpg .jpeg .png .pdf).freeze
IMG_EXTNAMES = %w(.jpg .jpeg .png .gif .bmp).freeze
LANGUAGE = 'en'.freeze
MESSAGES = YAML.load_file('cms_messages.yml')

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
  return File.expand_path("../#{path}", __FILE__) if ENV['RACK_ENV'] != 'test'
  File.expand_path("../test/#{path}", __FILE__)
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
  File.open(File.join(data_path, name), 'w') { |file| file.write(content) }
end

before do
  headers['Content-Type'] = 'text/html;charset=utf-8'
  @users = load_user_credentials

  pass unless restricted_route?
  redirect_unauthorized_user
end

before %r{/(\w.[^\/]+\.(?!.*\.)\w{2,})} do |filename|
  ext = File.extname(filename)
  @filename = filename
  @dirpath = IMG_EXTNAMES.include?(ext) ? image_path : data_path
  @filepath = File.join(@dirpath, @filename)

  redirect_unless_file_exists
end

before '/users/:action' do |action|
  pass unless action.casecmp('signin').zero? || action.casecmp('signup').zero?
  redirect_logged_in_user
end

helpers do
  def file_list(directory = nil)
    abs_path = directory.nil? ? data_path : File.join(data_path, directory)
    Dir.glob(File.join(abs_path, '*.*')).map { |path| File.basename(path) }
  end

  def flash_message(message, var = nil, key = :message)
    session[key] ||= format(MESSAGES[LANGUAGE][message], var: var).to_s
  end

  def redirect_unless_file_exists
    return if File.exist?(@filepath)
    redirect_with_message('/', 'file_doesnt_exist', File.basename(@filepath))
  end

  def redirect_with_message(route, *message)
    flash_message(*message)
    redirect(route)
  end

  def render_markdown(text)
    Redcarpet::Markdown.new(Redcarpet::Render::HTML).render(text)
  end

  def load_file_content(path)
    case File.extname(path)
    when '.txt', '.pdf', '.doc'
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
    return flash_message('username_too_short') if username.size < 2
    return flash_message('username_invalid_chars') if username =~ /\W/
    return flash_message('username_taken') if @users[username]
  end

  def invalid_password(password, password2)
    return flash_message('password_too_short') if password.size < 4
    return flash_message('password_invalid_chars') unless password =~ /\w+/
    return flash_message('passwords_dont_match') if password != password2
  end

  def signed_in?
    session[:username]
  end

  def restricted_route?
    RESTRICTED.include?(request.path_info.split('/')[2])
  end

  def redirect_unauthorized_user
    redirect_with_message(request.referrer, 'restricted') unless signed_in?
  end

  def redirect_logged_in_user
    redirect_with_message(request.referrer, 'already_signed_in') if signed_in?
  end

  def invalid_filename(name)
    return flash_message('filename_invalid') unless name =~ /\w+\.\w{2,}/
    unless VALID_FILE_EXTENSIONS.include?(File.extname(name))
      return flash_message('invalid_extname', VALID_FILE_EXTENSIONS.join(', '))
    end
    return flash_message('filename_taken', name) if file_list.include?(name)
  end

  def create_duplicate_file_name
    current_files = file_list
    basename = File.basename(@filename, @filename.match(/\d*\.\w{2,}/).to_s)
    copy_number = @filename.match(/\d+(?!.*\d+)/).to_s.to_i + 1

    loop do
      new_filename = "#{basename}#{copy_number}#{File.extname(@filename)}"
      return new_filename unless current_files.include?(new_filename)
      copy_number += 1
    end
  end

  def revisions_dir
    @filename.reverse.sub('.', '').reverse
  end

  def save_old_content
    file_ext = File.extname(@filename)
    old_content = File.read(@filepath)

    dir = revisions_dir
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

get('/files/new') { erb :new_file }

post '/files/create' do
  filename = params[:document_name]

  if invalid_filename(filename)
    status(422)
    halt erb(:new_file)
  end

  create_document(filename)
  redirect_with_message('/', 'file_new', filename)
end

get '/:filename/edit' do
  @file_content = File.read(@filepath)
  headers['Content-Type'] = 'text/html;charset=utf-8'
  erb :edit_file
end

post '/:filename/edit' do
  save_old_content
  edited_content = params[:file_content]
  File.open(@filepath, 'w') { |file| file.write(edited_content) }

  redirect_with_message('/', 'file_updated', @filename)
end

get '/:filename/revisions' do
  @revisions = file_list(revisions_dir).map { |f| File.basename(f, '.*') }
  erb :revisions
end

get '/:filename/revisions/:number' do |filename, number|
  revision_name = "#{number}#{File.extname(filename)}"
  load_file_content(File.join(data_path, "#{revisions_dir}/#{revision_name}"))
end

post '/files/delete/:filename' do
  revisions = @filepath.reverse.sub('.', '').reverse
  FileUtils.rm_rf(revisions, secure: true) if File.directory?(revisions)

  File.delete(@filepath)

  halt(204) if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
  redirect_with_message('/', 'file_deleted', @filename)
end

post '/files/duplicate/:filename' do
  new_filename = create_duplicate_file_name
  destination_path = File.join(data_path, new_filename)
  FileUtils.cp(@filepath, destination_path)

  redirect_with_message('/', 'file_new', new_filename)
end

get('/users/signup') { erb :signup }

post '/users/signup' do
  username = params[:username]
  password = params[:password]
  password2 = params[:password2]

  if invalid_username(username) || invalid_password(password, password2)
    halt erb(:signup)
  end

  @users[username] = { 'password' => encrypt(password) }
  File.open(credentials_path, 'w') do |file|
    file.write(@users.to_yaml) # or file.puts(YAML.dump(@users))
  end

  session[:username] = username
  redirect_with_message('/', 'welcome', username)
end

get('/users/signin') { erb :signin }

post '/users/signin' do
  username = params[:username]
  password = params[:password]

  user = @users[username]
  session[:username] = username if user && check?(password, user['password'])
  redirect_with_message('/', 'welcome', username) if signed_in?

  status(422)
  flash_message('invalid_credentials')
  erb :signin
end

post '/users/signout' do
  redirect_with_message(request.referrer, 'goodbye', session.delete(:username))
end

get(%r{/(.+\.(?!.*\.)\w{2,})}) { load_file_content(@filepath) }

get('/files/upload') { erb :upload }

post '/files/upload' do
  params[:files].each do |file|
    filename = params[file[:filename]] || file[:filename]
    FileUtils.cp(file[:tempfile].path, File.join(image_path, filename))
  end

  redirect('/')
end
