# frozen_string_literal: true

require 'rake'
require 'rspec/core'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require 'bundler/gem_tasks'

RSpec::Core::RakeTask.new(:spec)

desc 'Run RuboCop'
RuboCop::RakeTask.new(:rubocop)

task default: %i[spec rubocop]
