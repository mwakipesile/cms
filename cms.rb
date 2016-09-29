require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'

root = File.expand_path("..", __FILE__)

before do
  @flash_message = {}  
end

helpers do


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

  headers['Content-Type'] = 'text/plain'
  File.read(filepath)
end
