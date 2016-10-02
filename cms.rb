require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

configure do
  enable :sessions
  set :session_secret, 'password1'
  set :erb, :escape_html => true
end

before do
  headers["Content-Type"] = "text/html;charset=utf-8"
end

helpers do
  def render_markdown(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(text)
  end

  def load_file_content(path)
    content = File.read(path)
    case File.extname(path)
    when ".txt"
      headers["Content-Type"] = "text/plain"
      content
    when ".md"
      @content = render_markdown(content)
      erb :file
    end
  end
end

get "/" do
  @filenames = Dir.glob(File.join(data_path, "*")).map do |path|
    File.basename(path)
  end

  erb :index
end

get '/:filename/edit' do |filename|
  @filename = filename
  @file_content = File.read(File.join(data_path, filename))
  headers["Content-Type"] = "text/html;charset=utf-8"

  erb :edit_file
end

get "/*.*" do |filename, ext|
  filepath = "#{data_path}/#{filename}.#{ext}"

  if File.exist?(filepath)
    load_file_content(filepath)
  else
    session[:message] = "#{filename}.#{ext} does not exist."
    redirect('/')
  end
end

post '/:filename' do |filename|
  filepath = File.join(data_path, filename)
  text = params[:file_content]

  File.open(filepath, "w") { |file| file.write(text) }

  session[:message] = "#{filename} has been updated!"
  redirect("/")
end

get '/new' do
  erb :new_file
end
