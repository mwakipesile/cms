require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'

configure do
  enable :sessions
  set :session_secret, 'password1'
  set :erb, :escape_html => true
end

root = File.expand_path("..", __FILE__)

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
      render_markdown(content)
    end
  end
end

get "/" do
  @filenames = Dir.glob(root + "/data/*").map do |path|
    File.basename(path)
  end

  erb :index
end

get '/:filename/edit' do |filename|
  @filename = filename
  @file_content = load_file_content("#{root}/data/#{filename}")
  headers["Content-Type"] = "text/html;charset=utf-8"

  erb :edit_file
end

get "/*.*" do |filename, ext|
  filepath = "#{root}/data/#{filename}.#{ext}"

  if File.exist?(filepath)
    load_file_content(filepath)
  else
    session[:message] = "#{filename}.#{ext} does not exist."
    redirect('/')
  end
end

post '/:filename' do |filename|
  filepath = "#{root}/data/#{filename}"
  text = params[:file_content]
  File.open(filepath, "w") { |file| file.write(text) }

  redirect("/#{filename}")
end
