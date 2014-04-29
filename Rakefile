require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << ['lib', 'specs']
  t.test_files = FileList['specs/*_spec.rb']
  t.verbose = true
end

task :benchmark do
  system('ruby', "-Ilib", 'lib/custom_source_control.rb', '--benchmark', out: $stdout, err: :out)
end
