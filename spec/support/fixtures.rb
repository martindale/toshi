def fixtures_file(relative_path)
  dir = Dir["./spec/fixtures"]
  File.read File.join(dir, relative_path)
end
