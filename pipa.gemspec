Gem::Specification.new do |s|
  s.name        = 'pipa'
  s.version     = '0.2.1'
  s.date        = '2017-05-18'
  s.summary     = "Pipelines, easy"
  s.description = "Define and execute pipelines"
  s.authors     = ["Miguel Cantón Cortés"]
  s.email       = 'miwelc@gmail.com'
  s.files       = ["lib/pipa.rb"]
  s.executables = ["pipa"]
  s.homepage    = 'http://rubygems.org/gems/pipa'
  s.license     = 'MIT'
  s.add_dependency 'colorize', '~> 0.8.1'
  s.add_dependency 'httpclient', '~> 2.8.3'
  s.add_dependency 'json', '~> 2.1.0'
end