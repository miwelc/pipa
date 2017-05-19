require 'set'
require 'open3'
require 'colorize'

class Pipa
	def initialize(stages)
		@stages = stages
		@to_be_executed = Set.new( stages.map{|k,v| k} )
		@executed = Set.new
		@log = {}
		@ret = {}

		@stages.each do |name, attributes|
			attributes["dependencies"] ||= []
			attributes["dependencies_set"] = Set.new(attributes["dependencies"])
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
		unless @to_be_executed.empty?
			log_error "Some stages couldn't be executed: #{@to_be_executed.to_a}"
		end
		@success
	end

	private

	def log_info(msg)
		puts
		puts "-------- [#{Time.now.utc}] --------".green
		puts msg.green
		puts "-------------------------------------------".green
	end

	def log_error(msg)
		puts
		puts "-------- [#{Time.now.utc}] --------".red
		puts msg.red
		puts "-------------------------------------------".red
	end

	def resolved_dependencies?(stage)
		@stages[stage]["dependencies_set"].subset?(@executed)
	end

	def execute_stage(stage)
		log_info "Executing #{stage}."

		@threads << Thread.new do
			t = Time.now

			reader, writer = IO.pipe

			mode = ["bash","ruby","node","http"].find {|m| !@stages[stage][m].nil?}
			input = @stages[stage]["dependencies"].map{|d| "___deserialize(#{@ret[d].dump})"}.join(',')

			cmd = case mode
				when "bash"
					["ruby", "-e", %Q(
						require 'json'
						require 'open3'

						Open3.popen2e("bash", "-e", "-c", #{@stages[stage][mode].dump}) do |stdin, stdout_err, wait_thr|
							ret = ""
							while line = stdout_err.readpartial(4096) rescue nil
								print line
								$stdout.flush
								ret += line
							end

							exit_status = wait_thr.value
							if exit_status.success?
								ret_fd = IO.open(3, 'w')
								ret_fd.write(ret.to_json);
								ret_fd.close
							end
							exit(exit_status.exitstatus)
						end
					)]
				when "ruby"
					["ruby", "-e", %Q(
						require 'json'
						def ___deserialize(val)
							JSON.parse("[\#{val}]")[0]
						end
						#{@stages[stage][mode]};
						___n_args = method(:main).arity
						___input = [#{input}]
						___input = ___input.take(___n_args) if ___n_args >= 0
						___ret = main(*___input)
						___ret_fd = IO.open(3, 'w')
						___ret_fd.write(___ret.to_json);
						___ret_fd.close
					)]
				when "node"
					["node", "-e", %Q(
						___deserialize = JSON.parse
						#{@stages[stage][mode]};
						const ___ret = main(#{input});
						fs.writeSync(3, JSON.stringify(___ret));
					)]
				when "http"
					["ruby", "-e", %Q(
						require 'httpclient'
						require 'json'
						puts ___ret = HTTPClient.get_content("#{@stages[stage][mode]}")
						___ret_fd = IO.open(3, 'w')
						___ret_fd.write(___ret.to_json);
						___ret_fd.close
					)]
			end

			@log[stage] = ""
			@ret[stage] = ""

			Open3.popen2e(*cmd, 3 => writer.fileno) do |stdin, stdout_err, wait_thr|
				ret_thread = Thread.new do
					while line = reader.readpartial(4096) rescue nil
						@ret[stage] << line
					end
					reader.close
				end

				while line = stdout_err.readpartial(4096) rescue nil
					print line
					@log[stage] << line
				end

				exit_status = wait_thr.value

				writer.close
				ret_thread.join

				exit_status = wait_thr.value
				if exit_status.success?
					@executed.add(stage)
					log_info "Stage '#{stage}' took #{Time.now - t}s."
				else
					log_error "Stage '#{stage}' failed with status #{exit_status.exitstatus} after #{Time.now - t}s. Error msg:\n#{@log[stage]}"
					@success = false
				end

				execute
			end
		end
	end
end