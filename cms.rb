require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'

root = File.expand_path("..", __FILE__)

before do
  @flash_message = {}  
end

helpers do
  def load_content(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(text)
  end
end

get "/" do
  headers["Content-Type"] = "text/html;charset=utf-8"
  @filenames = Dir.glob(root + "/data/*").map do |path|
    File.basename(path)
  end

  erb :index
end

get "/*.*" do |filename, ext|
  filepath = "#{root}/data/#{filename}.#{ext}"
  
  unless File.exist?(filepath)
    @flash_message[:not_found] = "#{filename}.#{ext} does not exist."
    redirect('/')
  end

  text = File.read(filepath)
  if ext == 'md'
    headers['Content-Type'] = "text/html;charset=utf-8"
    load_content(text)
  else
    headers['Content-Type'] = "text/plain"
    text
  end
end
