require 'sinatra'
require 'google/cloud/storage'
require 'json'
require 'digest'
require 'stringio'


regex = /^[a-f0-9]{64}$/

def validate(string)
  if string.length== 64 and !string.match(/^[a-f0-9]{64}$/).nil?
    return true
  else
    return false
  end
end

get '/' do
  redirect '/files/', 302
end

get '/files/' do 
  storage = Google::Cloud::Storage.new(project_id: 'cs291a')
  bucket = storage.bucket 'cs291project2', skip_lookup: true
  all_files = bucket.files
  
  # check for validity of files, sort valid files and return as a sorted list
  valid_files = Array[]
  all_files.all do |file|
    filename = file.name
    downcase_filename = filename.downcase
    form = filename.split('/')
    if form.length == 3 and form[0].length == 2 and form[1].length == 2 and form[2].length == 60
      if validate(form[0]+form[1]+form[2]) # check if name only contains legit hash characters
        valid_files << (form[0]+form[1]+form[2])
      end
    end
    
  end
  sorted_files = valid_files.sort

  r = Array[200, {"Content-Type" => "application/json"}, sorted_files.to_json]
  return r
end

post '/files/' do
  puts params
  file_handle = params[:file]
  if file_handle.nil? or file_handle == ''
    return Array[422, "file missing or no name\n"]
  end

  tempfile = params['file']['tempfile']

  if tempfile.nil? or !File.file?(tempfile)
    return [422, "file empty"]
  end

  if tempfile.size() > 1024 * 1024
    puts tempfile.size()
    return Array[422, "file too large"]
  end

  # compute and compare SHA256
  begin
    tempfile.read
  rescue
    return Array[422, "empty file"]
  else
    tempfile.rewind
    digest = Digest::SHA256.hexdigest(tempfile.read)
    puts "digest:", digest
    original_digest = digest 
    digest = digest.downcase
    digest.insert(2, '/')
    digest.insert(5, '/')
    puts "digest", digest
    storage = Google::Cloud::Storage.new(project_id: 'cs291a')
    bucket = storage.bucket 'cs291project2', skip_lookup: true
    file_lookup = bucket.file digest, skip_lookup: false
	  if file_lookup
		  return Array[409, "SHA256 hex digest already exists\n"]
	  end
    
    # successfully upload the file
    bucket.create_file File.new(tempfile), digest, content_type: params['file']['type']
    return Array[201, {"Content-Type" => "application/json"}, { uploaded: original_digest }.to_json]
  end
end


get '/files/:digest' do
	digest = params['digest']
  digest = digest.downcase
  return [422, 'Digest Not Valid\n'] unless params['digest'].downcase.match(regex)
  
  # format digest
	digest.insert(4, "/")
	digest.insert(2, "/")
  
  # storage access
	storage = Google::Cloud::Storage.new(project_id: 'cs291a')
	bucket = storage.bucket 'cs291project2', skip_lookup: true
	file_lookup = bucket.file digest, skip_lookup: true

	if !file_lookup&.exists? 
		return Array[404, "File not found!"]
	end

	content = file_lookup.content_type
	downloaded = file_lookup.download
	return Array[200, {"Content-Type" => content}, downloaded.read]
end

delete '/files/:digest' do
  filename = params['digest']
  return [422, 'Digest Not Valid\n'] unless filename.downcase.match(regex)

  filename = filename.downcase

  filename.insert(2, "/")
  filename.insert(5, "/")

  storage = Google::Cloud::Storage.new(project_id: 'cs291a')
  bucket = storage.bucket 'cs291project2', skip_lookup: true
  all_files = bucket.files

  all_files.all do |file|
    if file.name == filename
      file.delete
      return Array[200, 'Deleted the file']
    end
  end
  return Array[200, 'Deleted the file'] # to make delete idempotent
end
