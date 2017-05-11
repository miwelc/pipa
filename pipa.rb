require 'yaml'
require 'set'
require 'open3'

class Pipa
	def initialize(stages)
		@stages = stages
		@to_be_executed = Set.new( stages.map{|k,v| k} )
		@executed = Set.new

		@stages.each do |name, attributes|
			attributes["dependencies_set"] = Set.new(attributes["dependencies"] || [])
		end

		@threads = []

		@success = true
	end

	def execute
		@to_be_executed.delete_if do |stage|
			if resolved_dependencies? stage
				execute_stage(stage)
				true
			else
				false
			end
		end
	end

	def wait
		@threads.map(&:join)
		@success
	end

	private

	def resolved_dependencies?(stage)
		@stages[stage]["dependencies_set"].subset?(@executed)
	end

	def execute_stage(stage)
		@threads << Thread.new do
			t = Time.now

			mode = ["bash","ruby","node"].find {|m| !@stages[stage][m].nil?}

			cmd = ["bash", "-e", "-c", "#{@stages[stage][mode]}"] if mode == "bash"
			cmd = ["ruby", "-e", "#{@stages[stage][mode]};main()"] if mode == "ruby"
			cmd = ["node", "-e", "#{@stages[stage][mode]};main()"] if mode == "node"

			Open3.popen2e(*cmd) do |stdin, stdout_err, wait_thr|
				while line = stdout_err.gets
					puts line
				end

				exit_status = wait_thr.value
				if exit_status.success?
					@executed.add(stage)
				else
					puts "Stage '#{stage}' failed with status #{exit_status.exitstatus}."
					@success = false
				end

				execute
			end

			puts "Stage '#{stage}' took #{Time.now - t}s."
		end
	end
end

config = YAML.load(IO.read(ARGV[0]))

pipa = Pipa.new(config["stages"])
pipa.execute
pipa.wait